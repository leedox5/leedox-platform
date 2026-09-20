# Handoff 0058 -- tells "the storage backend is unavailable" (network, timeout,
# credentials, provider error) apart from ordinary bugs, without loading the AWS
# SDK constants up front. Callers turn these into a 503 instead of a 500, and
# never leak the provider's message to the customer.
module StorageFailures
  CLASS_NAMES = %w[
    SystemCallError IOError SocketError Timeout::Error EOFError
    Seahorse::Client::NetworkingError Aws::Errors::ServiceError Aws::Errors::MissingCredentialsError
    Aws::Sigv4::Errors::MissingCredentialsError Aws::S3::Errors::ServiceError
    ActiveStorage::IntegrityError ActiveStorage::Service::ConfigurationError
  ].freeze

  # The object is not in storage. Depending on the client and the call, S3
  # reports this as a false/404 or as an error -- both mean "missing", never
  # "storage is down".
  MISSING_CLASS_NAMES = %w[
    ActiveStorage::FileNotFoundError Aws::S3::Errors::NotFound Aws::S3::Errors::NoSuchKey Errno::ENOENT
  ].freeze

  UNAVAILABLE_MESSAGE = "파일 저장소에 일시적인 문제가 있습니다. 잠시 후 다시 시도해 주세요.".freeze
  MISSING_MESSAGE = "파일을 찾을 수 없습니다.".freeze

  def self.missing_error?(error)
    error.class.ancestors.any? { |ancestor| MISSING_CLASS_NAMES.include?(ancestor.name) }
  end

  def self.storage_error?(error)
    return false if missing_error?(error)

    error.class.ancestors.any? { |ancestor| CLASS_NAMES.include?(ancestor.name) }
  end
end
