# Manual snapshot of the DB-backed service desk into the same fenced-header
# .md format documented in leedox-hq's service-desk/GUIDE.md, zipped
# for download. Purely a backup — nothing here writes back to git or to
# hq/service-desk/, and nothing runs this automatically.
class ServiceDeskExport
  LABEL_WIDTH = 11

  def to_zip
    buffer = Zip::OutputStream.write_buffer do |zip|
      ServiceDeskRequest.order(:request_number).each do |request|
        zip.put_next_entry("#{padded(request.request_number)}.md")
        zip.write(render_request(request))
      end
    end

    buffer.rewind
    buffer.read
  end

  private

  def render_request(request)
    <<~MARKDOWN
      ```text
      #{field("ID", padded(request.request_number))}
      #{field("Date", request.date.strftime('%Y.%m.%d'))}
      #{field("Requester", request.requester)}
      #{field("Subject", request.subject)}
      #{field("Status", request.status_label)}
      #{field("Visibility", request.visibility_label)}
      ```

      Description :
      ```text
      #{request.description}
      ```

      Job :
      ```text
      #{render_jobs(request)}
      ```
    MARKDOWN
  end

  def render_jobs(request)
    request.service_desk_jobs.order(:job_number).map do |job|
      "#{padded(job.job_number)} #{job.author} #{job.performed_at.strftime('%Y.%m.%d %H:%M')}\n#{job.content}"
    end.join("\n\n")
  end

  def field(label, value)
    "#{label.rjust(LABEL_WIDTH)} : #{value}"
  end

  def padded(number)
    number.to_s.rjust(4, "0")
  end
end
