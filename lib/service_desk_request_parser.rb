# Parses the git-based service-desk request format documented in
# leedox-hq's service-desk/GUIDE.md: a fenced ID/Date/Requester/
# Subject/Status/Visibility header, a fenced Description block, and a fenced
# Job block whose entries each start with a "NNNN Author YYYY.MM.DD HH:MM"
# header line. Used only by the one-time DB import (lib/tasks/service_desk_import.rake)
# and its verification — the git files themselves stay untouched and unsynced.
class ServiceDeskRequestParser
  JOB_HEADER_PATTERN = /\A(\d{4})\s+(\S+)\s+(\d{4}\.\d{2}\.\d{2})\s+(\d{2}:\d{2})\z/

  Result = Struct.new(:id, :date, :requester, :subject, :status, :visibility, :description, :jobs, keyword_init: true)
  Job = Struct.new(:job_number, :author, :performed_at, :content, keyword_init: true)

  def self.parse(raw_markdown)
    new(raw_markdown).parse
  end

  def initialize(raw_markdown)
    @raw = raw_markdown
  end

  def parse
    header_block, description_block, job_block = fenced_blocks
    header = parse_header(header_block)

    Result.new(
      id: header[:id],
      date: header[:date],
      requester: header[:requester],
      subject: header[:subject],
      status: header[:status],
      visibility: header[:visibility],
      description: description_block.to_s.strip,
      jobs: parse_jobs(job_block)
    )
  end

  private

  def fenced_blocks
    blocks = @raw.scan(/```[^\n]*\n(.*?)\n```/m).map(&:first)
    raise "Expected 3 fenced blocks (header, description, job), found #{blocks.size}" unless blocks.size == 3

    blocks
  end

  # Header lines are positional (ID, Date, Requester, Subject, Status,
  # Visibility, in that fixed order) rather than matched by label text, since
  # at least one source file has a "Reqeuster" typo instead of "Requester".
  def parse_header(header_block)
    values = header_block.lines.map(&:strip).reject(&:empty?).map { |line| line.split(":", 2)[1].to_s.strip }
    raise "Expected 6 header lines, found #{values.size}" unless values.size == 6

    {
      id: values[0],
      date: Date.strptime(values[1], "%Y.%m.%d"),
      requester: values[2],
      subject: values[3],
      status: values[4],
      visibility: values[5]
    }
  end

  def parse_jobs(job_block)
    jobs = []
    current = nil

    job_block.to_s.split("\n").each do |line|
      if (match = line.strip.match(JOB_HEADER_PATTERN))
        jobs << finalize(current) if current
        current = {
          job_number: match[1].to_i,
          author: match[2],
          performed_at: Time.zone.parse("#{match[3].tr('.', '-')} #{match[4]}"),
          content_lines: []
        }
      elsif current
        current[:content_lines] << line
      end
    end
    jobs << finalize(current) if current

    jobs
  end

  def finalize(job)
    Job.new(
      job_number: job[:job_number],
      author: job[:author],
      performed_at: job[:performed_at],
      content: job[:content_lines].join("\n").strip
    )
  end
end
