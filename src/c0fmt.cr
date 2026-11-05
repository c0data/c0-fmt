require "jargon"
require "c0"
require "c0/csv"
require "c0/json"

SCHEMA = <<-YAML
---
name: import
description: Import CSV, JSON, or YAML into C0DATA compact format
positional:
  - format
  - file
properties:
  format:
    type: string
    description: Input format (csv, json, yaml) or input file. Auto-detected if omitted.
  file:
    type: string
    description: Input file (reads stdin if omitted)
  output:
    type: string
    short: o
    description: Output file (stdout if omitted)
  group:
    type: string
    short: g
    description: Group name (defaults to filename stem or 'data')
---
name: export
description: Export C0DATA to CSV, JSON, or YAML
positional:
  - format
  - file
required:
  - format
properties:
  format:
    type: string
    enum: [csv, json, yaml]
    description: Output format
  file:
    type: string
    description: Input C0DATA file (reads stdin if omitted)
  output:
    type: string
    short: o
    description: Output file (stdout if omitted)
  group:
    type: string
    short: g
    description: Group to export (csv only; default the first group)
---
name: pretty
description: Convert C0DATA to pretty-printed Unicode form
positional:
  - file
properties:
  file:
    type: string
    description: Input file (reads stdin if omitted)
  output:
    type: string
    short: o
    description: Output file (stdout if omitted)
  align:
    type: boolean
    short: a
    description: Align table columns (layout only; never changes the data)
---
name: compact
description: Convert C0DATA to compact binary form
positional:
  - file
properties:
  file:
    type: string
    description: Input file (reads stdin if omitted)
  output:
    type: string
    short: o
    description: Output file (stdout if omitted)
---
name: validate
description: Validate C0DATA structure
positional:
  - file
properties:
  file:
    type: string
    description: Input file (reads stdin if omitted)
  stream:
    type: boolean
    short: s
    description: Validate as a stream-mode log (report torn tail and damaged blocks)
  canonical:
    type: boolean
    short: c
    description: Also require canonical form (no layout, one spelling per value, unique keys)
YAML

cli = Jargon.cli("c0fmt", yaml: SCHEMA)

# Shell completion. Jargon generates the scripts (`c0fmt --completions
# bash|zsh|fish`) and completes subcommands, flags, and enum values on its
# own; those scripts turn off the shell's native filename completion, so
# path-valued arguments are completed here.
FORMATS = %w[csv json yaml]

{"import.file", "import.output", "export.file", "export.output",
 "pretty.file", "pretty.output", "compact.file", "compact.output",
 "validate.file"}.each do |field|
  cli.completer(field) { |ctx| path_candidates(ctx.partial) }
end

# The first positional of `import` is a format or, when omitted, the file.
cli.completer("import.format") do |ctx|
  FORMATS.select(&.starts_with?(ctx.partial)) + path_candidates(ctx.partial)
end

cli.run do |result|
  run(result)
rescue ex : C0::Error
  STDERR.puts "c0fmt: #{ex.message}"
  exit 1
end

def run(result) : Nil
  input_file = result["file"]?.try(&.as_s)
  output_file = result["output"]?.try(&.as_s)

  # Read input from file or stdin
  input = read_input(input_file)

  res = case result.subcommand
        when "import"
          # First positional could be a format (csv/json/yaml) or a file path
          raw_format = result["format"]?.try(&.as_s)
          if raw_format && !{"csv", "json", "yaml"}.includes?(raw_format)
            # It's actually a file path, not a format
            input_file = raw_format
            input = read_input(input_file)
            raw_format = nil
          end
          format = raw_format || detect_format(input_file, input)
          gname = result["group"]?.try(&.as_s) || input_file.try { |f| File.basename(f, File.extname(f)) } || "data"

          buf = case format
                when "csv"  then C0::CSV.from_csv(input, group_name: gname)
                when "json" then C0::JSON.from_json(input, group_name: gname)
                when "yaml" then C0::JSON.from_yaml(input, group_name: gname)
                else
                  STDERR.puts "Cannot detect input format. Specify: c0fmt import <csv|json|yaml> [file]"
                  exit 1
                end
          String.new(buf)
        when "export"
          format = result["format"].as_s
          buf = to_compact(input)

          case format
          when "csv"  then C0::CSV.to_csv(buf, result["group"]?.try(&.as_s))
          when "json" then C0::JSON.to_json(buf)
          when "yaml" then C0::JSON.to_yaml(buf)
          else             raise "unreachable"
          end
        when "pretty"
          buf = to_compact(input)
          pretty = C0::Pretty.format(buf)
          result["align"]?.try(&.as_bool) ? C0::Pretty.align(pretty) : pretty
        when "compact"
          buf = to_compact(input)
          String.new(buf)
        when "validate"
          buf = to_compact(input)
          exit validate(buf, stream: result["stream"]?.try(&.as_bool) || false,
            canonical: result["canonical"]?.try(&.as_bool) || false)
        end

  # Write output
  if res
    if file = output_file
      File.write(file, res)
    else
      print res
    end
  end
end

# The input file, or stdin when none is given.
def read_input(file : String?) : String
  file ? File.read(file) : STDIN.gets_to_end
rescue ex : File::Error
  STDERR.puts "c0fmt: #{ex.message}"
  exit 2
end

# Check structure (and canonical form on request), print a verdict to
# stderr, return the exit status. A stream log is checked block by block:
# the committed part must be well-formed, damaged blocks and an uncommitted
# tail are reported.
def validate(buf : Bytes, stream : Bool, canonical : Bool) : Int32
  if stream
    reader = C0::Stream::Reader.new(buf)
    begin
      C0.validate(reader.committed)
    rescue ex : C0::Error
      STDERR.puts "invalid: #{ex.message}"
      return 1
    end
    status = 0
    unless reader.damaged.empty?
      STDERR.puts "damaged: block(s) #{reader.damaged.join(", ")} of #{reader.block_count}"
      status = 1
    end
    if reader.torn?
      STDERR.puts "torn: #{reader.tail.size} uncommitted byte(s) after " \
                  "#{reader.block_count} committed block(s)"
      status = 1
    end
    STDERR.puts "valid: #{reader.block_count} committed block(s)" if status == 0
    return status
  end

  begin
    C0.validate(buf)
  rescue ex : C0::Error
    STDERR.puts "invalid: #{ex.message}"
    return 1
  end
  C0::Container.new(buf).documents.each do |doc|
    doc.warnings.each { |w| STDERR.puts "warning: #{w}" }
  end
  if canonical
    # A canonical file is SYN, a heading with unique keys, a canonical
    # body, EOT: the markers and heading are outside the unit.
    why = [] of String
    C0::Container.new(buf).documents.each do |doc|
      keys = doc.heading.keys
      why << "duplicate heading key" if keys.size != keys.uniq.size
      v = C0::Validator.new(doc.body.raw, canonical: true)
      v.run
      why.concat(v.warnings)
    end
    unless why.empty?
      why.uniq.each { |w| STDERR.puts "not canonical: #{w}" }
      return 1
    end
  end
  STDERR.puts(canonical ? "valid, canonical" : "valid")
  0
end

# Filesystem entries matching a partially typed path, directories with a
# trailing slash. Dotfiles are offered only once a dot has been typed.
def path_candidates(partial : String) : Array(String)
  dir, prefix = if i = partial.rindex('/')
                  {partial[0..i], partial[(i + 1)..]}
                else
                  {"", partial}
                end
  lookup = dir.empty? ? "." : dir
  lookup = Path[lookup].expand(home: true).to_s if lookup.starts_with?('~')
  return [] of String unless Dir.exists?(lookup)

  Dir.children(lookup)
    .select { |name| name.starts_with?(prefix) && (prefix.starts_with?('.') || !name.starts_with?('.')) }
    .sort!
    .map { |name| File.directory?(File.join(lookup, name)) ? "#{dir}#{name}/" : "#{dir}#{name}" }
rescue File::Error
  [] of String
end

# Detect if input contains Unicode Control Pictures (pretty format)
def pretty_input?(input : String) : Bool
  input.each_char do |c|
    return true if c.ord >= 0x2400 && c.ord <= 0x241F
  end
  false
end

# Convert input to compact bytes, auto-detecting pretty vs compact
def to_compact(input : String) : Bytes
  if pretty_input?(input)
    C0::Pretty.parse(input)
  else
    input.to_slice
  end
end

# Auto-detect import format from file extension or content sniffing
def detect_format(file : String?, content : String) : String?
  # Try file extension first
  if f = file
    case File.extname(f).downcase
    when ".csv"          then return "csv"
    when ".json"         then return "json"
    when ".yaml", ".yml" then return "yaml"
    end
  end

  # Sniff content
  trimmed = content.lstrip
  if trimmed.starts_with?('{') || trimmed.starts_with?('[')
    "json"
  elsif trimmed.starts_with?("---")
    "yaml"
  else
    "csv"
  end
end
