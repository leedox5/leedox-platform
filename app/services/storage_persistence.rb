require "active_storage/service/disk_service" # not autoloaded when only the bucket service is configured

# Handoff 0058 -- production must never accept an upload onto the container's
# own disk: that disk is replaced on every deploy, so the database would keep a
# file record whose file is gone. While ACTIVE_STORAGE_SERVICE is unset (the
# :local fallback) uploads are refused with a clear message instead. The
# refusal is by service class, not by environment name, so it also protects a
# production-like setup that points at a Disk service.
module StoragePersistence
  MESSAGE = "파일 저장소가 아직 영속 저장소(버킷)로 설정되지 않아 지금은 업로드할 수 없습니다. " \
            "설정이 끝나면 다시 시도해 주세요.".freeze

  # Overridable so tests can exercise the production rule.
  def self.enforced?
    Rails.env.production?
  end

  def self.upload_blocked?
    enforced? && ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::DiskService)
  end
end
