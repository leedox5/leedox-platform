require "aws-sdk-s3"
require "active_storage/service/s3_service"

# In-memory stand-in for the production S3-compatible bucket (handoff 0058).
# It is a real ActiveStorage::Service::S3Service whose AWS client answers from
# a Hash, so uploads (put_object), ranged downloads (get_object), existence
# checks (head_object) and deletes run through the same Active Storage / SDK
# code as production -- only the network is replaced.
class FakeBucket
  attr_reader :objects, :service
  # Set to an exception instance to make every call fail like an outage;
  # or set per operation with fail_on(:put_object, error).
  attr_accessor :outage

  def initialize(name: :fake_bucket)
    @objects = {}
    @failures = {}
    @service = ActiveStorage::Service::S3Service.new(
      bucket: "fake-private-bucket", region: "auto", endpoint: "https://bucket.invalid",
      access_key_id: "test", secret_access_key: "test", force_path_style: true,
      public: false, stub_responses: true
    )
    @service.name = name
    stub_operations
  end

  def fail_on(operation, error)
    @failures[operation] = error
  end

  def clear_failures
    @failures.clear
    @outage = nil
  end

  def keys
    @objects.keys
  end

  # Makes this the service new and existing blobs resolve to, for the block.
  def install
    registry = ActiveStorage::Blob.services
    services = registry.instance_variable_get(:@services)
    previous_default = ActiveStorage::Blob.service
    services[@service.name.to_sym] = @service
    ActiveStorage::Blob.service = @service
    yield self
  ensure
    ActiveStorage::Blob.service = previous_default
    services.delete(@service.name.to_sym)
  end

  private

  def stub_operations
    bucket = self
    client = @service.client.client
    outage_or = ->(operation, &block) { ->(ctx) { bucket.failure_for(operation) || block.call(ctx) } }

    client.stub_responses(:put_object, outage_or.call(:put_object) do |ctx|
      body = ctx.params[:body]
      @objects[ctx.params[:key]] = (body.respond_to?(:read) ? body.tap(&:rewind).read : body.to_s).b
      {}
    end)
    client.stub_responses(:head_object, outage_or.call(:head_object) do |ctx|
      data = @objects[ctx.params[:key]]
      data ? { content_length: data.bytesize, content_type: "application/octet-stream" } : "NotFound"
    end)
    client.stub_responses(:get_object, outage_or.call(:get_object) do |ctx|
      data = @objects[ctx.params[:key]]
      next "NoSuchKey" unless data

      range = ctx.params[:range]
      data = data.byteslice(Regexp.last_match(1).to_i..Regexp.last_match(2).to_i) if range =~ /bytes=(\d+)-(\d+)/
      { body: data }
    end)
    client.stub_responses(:list_objects_v2, outage_or.call(:list_objects_v2) do |_ctx|
      { contents: @objects.map { |key, data| { key: key, size: data.bytesize } }, is_truncated: false, key_count: @objects.size }
    end)
    client.stub_responses(:delete_object, outage_or.call(:delete_object) do |ctx|
      @objects.delete(ctx.params[:key])
      {}
    end)
  end

  public

  def failure_for(operation)
    @failures[operation] || @outage
  end
end
