require 'strscan'
require 'audit_log_parser/version'

class AuditLogParser
  class Error < StandardError; end

  # audit always uses uppercase hex digits. Fortunately addresses are generally lower-case.
  HEX_RE = /^[A-F0-9]{8,}$/

  def self.parse(src, flatten: false, unhex: false)
    src.each_line.map do |line|
      parse_line(line, flatten: flatten, unhex: unhex)
    end
  end

  def self.parse_line(line, flatten: false, unhex: false)
    line = line.strip

    if line !~ /type=\w+ msg=audit\([\d.:]+\): */
      raise Error, "Invalid audit log header: #{line.inspect}"
    end

    header, body = line.split(/\): */, 2)
    header << ')'
    header.sub!(/: *\z/, '')
    header = parse_header(header)
    body = parse_body(body.strip)

    if unhex
      unhex_hash!(header)
      unhex_hash!(body)
    end

    result = {'header' => header, 'body' => body}
    flatten ? flatten_hash(result) : result
  end

  def self.unhex_hash!(hash)
    hash.each do |key, value|
      if value.kind_of?(Hash)
        unhex_hash!(value)
      elsif (value.length % 2) == 0 && HEX_RE.match(value)
        value[0..-1] = [value].pack("H*")
      end
    end
  end

  def self.parse_header(header)
    result = {}

    header.split(' ').each do |kv|
      key, value = kv.split('=', 2)
      result[key] = value
    end

    result
  end
  private_class_method :parse_header

  def self.parse_body(body)
    if body.empty?
      return {}
    elsif !body.include?('=')
      raise Error, "Invalid audit log body: #{body.inspect}"
    end

    result = {}
    ss = StringScanner.new(body)

    while key = ss.scan_until(/=/)
      if key.include?(', ')
        msg, key = key.split(', ', 2)
        result['_message'] = msg.strip
      end

      key.chomp!('=').strip!
      value = ss.getch

      case value
      when nil
        break
      when ' '
        next
      when '"'
        value << ss.scan_until(/"/)
      when "'"
        nest = ss.scan_until(/'/)
        nest.chomp!("'")
        value = parse_body(nest)
      else
        value << ss.scan_until(/( |\z)/)
        value.chomp!(' ')
      end

      result[key] = value
    end

    unless ss.rest.empty?
      raise "must not happen: #{body}"
    end

    result
  end
  private_class_method :parse_body

  def self.flatten_hash(h)
    h.flat_map {|key, value|
      if value.is_a?(Hash)
        flatten_hash(value).map do |sub_key, sub_value|
          ["#{key}_#{sub_key}", sub_value]
        end
      else
        [[key, value]]
      end
    }.to_h
  end
  private_class_method :flatten_hash
end