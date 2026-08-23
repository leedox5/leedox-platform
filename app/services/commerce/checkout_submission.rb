module Commerce
  # Wraps OrderCreator with the "at most one pending order per user+product"
  # policy for real checkout-form submissions specifically. OrderCreator itself
  # stays a plain "create exactly the order asked for" primitive, since RetryOrder
  # and a number of existing tests rely on calling it directly, repeatedly, for
  # the same user+product+offer to set up independent fixtures/order lineages --
  # baking this dedup into OrderCreator broke that contract.
  class CheckoutSubmission
    def self.call!(user:, product_code:, offer_code:, requested_start_on:, provider:, at: Time.current)
      new(
        user: user,
        product_code: product_code,
        offer_code: offer_code,
        requested_start_on: requested_start_on,
        provider: provider,
        at: at
      ).call!
    end

    def initialize(user:, product_code:, offer_code:, requested_start_on:, provider:, at:)
      @user = user
      @product_code = product_code
      @offer_code = offer_code
      @requested_start_on = requested_start_on
      @provider = provider
      @at = at
    end

    def call!
      product = Product.find_by!(code: @product_code)
      existing_pending = find_existing_pending(product)

      if existing_pending
        # Reuse only if it's still the same thing the customer is asking for
        # right now -- same product/duration AND same payment method. A
        # provider mismatch (handoff: KakaoPay checkout choice) must not
        # silently hand back an old order under a different payment method
        # the customer isn't currently choosing (e.g. a stale manual-transfer
        # order from weeks ago, just because today's duration happens to
        # match) -- that would ignore what they picked today entirely.
        return existing_pending if existing_pending.order_items.first!.offer_code == @offer_code && existing_pending.provider == @provider
        return existing_pending unless Commerce::PendingOrderAssessment.evidence_free?(order: existing_pending)
      end

      ApplicationRecord.transaction do
        replace_pending_order!(existing_pending) if existing_pending

        Commerce::OrderCreator.call!(
          user: @user,
          product_code: @product_code,
          offer_code: @offer_code,
          requested_start_on: @requested_start_on,
          provider: @provider,
          at: @at
        )
      end
    end

    private

    def find_existing_pending(product)
      @user.orders.where(status: "pending")
        .joins(:order_items).where(order_items: { product_id: product.id })
        .order(created_at: :desc).first
    end

    # Re-locks and re-checks status: if the order was paid out from under us
    # between the initial read and here, leave it alone (paid orders are never
    # touched by this dedup logic) and just proceed to create the new order.
    def replace_pending_order!(existing)
      existing.lock!
      return unless existing.status == "pending"

      previous_status = existing.status
      existing.transition_to!("abandoned", abandoned_at: @at, finalized_at: @at)
      Commerce::AuditRecorder.record!(
        actor: @user,
        action: "order_abandoned",
        auditable: existing,
        from_state: previous_status,
        to_state: existing.status,
        reason_code: "replaced_by_new_offer_selection",
        at: @at
      )
    end
  end
end
