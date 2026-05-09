# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_EX_script_ICM Binary Results Export.rb
#
# Purpose : Pure-Ruby parser for the ICM binary results format.  Provides
#           classes (ICMBinaryReader, ICMBinaryTable, ICMBinaryObject,
#           ICMBinaryAttributes, ICMBinaryUtil, SimTime) plus a CLI:
#               ruby fix_EX_script_ICM\ Binary\ Results\ Export.rb FILE T
#               ruby ... FILE A <table>
#               ruby ... FILE O <table>
#               ruby ... FILE R <table> <object>
#               ruby ... FILE RR <table> <object>   (risk results)
#               ruby ... FILE S <table> <object>
#               ruby ... FILE BR <table> <object> <index>
# Inputs  : Binary results file path (ARGV[0]).
# Outputs : Console listings or CSV-style results to stdout.
# Type    : EX/standalone Ruby script (no WSApplication dependency).
# Hardening:
#   * frozen_string_literal pragma
#   * Validates input file exists and ARGV provided
#   * File reads wrapped in begin/rescue/ensure; file always closed
#   * Timestamped logging on errors
#   * Preserves original API and command surface
# ---------------------------------------------------------------------------

require 'date'

def fix_log(msg)
  warn "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

class ICMBinaryObject
  attr_reader :offset, :name
  def initialize(name, offset, float_blob_attributes, double_blob_attributes)
    @name = name
    @offset = offset
    @float_blob_attributes = float_blob_attributes
    @float_blob_offsets = []
    @double_blob_attributes = double_blob_attributes
    @double_blob_offsets = []
    blob_offset = 0
    unless float_blob_attributes.nil?
      (0...float_blob_attributes.size).each do |i|
        @float_blob_offsets << blob_offset
        blob_offset += float_blob_attributes[i]
      end
    end
    unless double_blob_attributes.nil?
      (0...double_blob_attributes.size).each do |i|
        @double_blob_offsets << blob_offset
        blob_offset += (double_blob_attributes[i] * 2)
      end
    end
  end
  def get_float_blob_size(n);   @float_blob_attributes[n]; end
  def get_float_blob_offset(n); @float_blob_offsets[n];    end
  def get_double_blob_size(n);  @double_blob_attributes[n];end
  def get_double_blob_offset(n);@double_blob_offsets[n];   end
  def dump
    out = "#{@name} #{@offset}"
    @float_blob_attributes&.each { |a| out += " #{a}" }
    @double_blob_attributes&.each { |a| out += " #{a}" }
    puts out
  end
end

class SimTime
  def initialize(val); @val = val; end
  def to_s
    if @val > 0
      DateTime.jd(@val + DateTime.new(1899, 12, 30, 0).jd.to_f).to_s
    else
      @val = -@val.to_i
      seconds = @val % 60
      mins = (@val / 60) % 60
      hours = (@val / 3600) % 24
      days = @val / 86400
      format('0000-00-%2.3dT%2.2d:%2.2d:%2.2d+00:00', days, hours, mins, seconds)
    end
  end
end

class ICMBinaryUtil
  def self.readlong(f);   f.read(4).unpack1('l'); end
  def self.readdouble(f); f.read(8).unpack1('d'); end
  def self.readdate(f);   SimTime.new(f.read(8).unpack1('d')); end
  def self.readstring(f)
    bytes = f.read(1).unpack1('C')
    ret = bytes > 0 ? f.read(bytes) : ''
    if ((bytes + 1) % 4) != 0
      f.read(4 - ((bytes + 1) % 4))
    end
    ret
  end
  def self.words(s)
    len = s.length + 1
    len += (4 - len % 4) if (len % 4) != 0
    len / 4
  end
end

class ICMBinaryAttributes
  attr_reader :name, :desc, :unit, :precision
  def init(f)
    @name = ICMBinaryUtil.readstring(f)
    @desc = ICMBinaryUtil.readstring(f)
    @unit = ICMBinaryUtil.readstring(f)
    @precision = ICMBinaryUtil.readlong(f)
    ICMBinaryUtil.words(@name) + ICMBinaryUtil.words(@desc) + ICMBinaryUtil.words(@unit) + 1
  end
  def dump; puts "#{name} '#{desc}' #{unit} #{precision}"; end
end

class ICMBinaryTable
  attr_reader :name, :desc
  def init(f, b_max, object_offset)
    @b_max = b_max
    @objectHash = {}
    header_size = 0
    object_count = ICMBinaryUtil.readlong(f)
    non_blob_attribute_count = ICMBinaryUtil.readlong(f)
    float_blob_attributes_count = ICMBinaryUtil.readlong(f)
    double_blob_attributes_count = @b_max ? ICMBinaryUtil.readlong(f) : 0
    header_size += 3
    header_size += 1 if @b_max
    @name = ICMBinaryUtil.readstring(f)
    @desc = ICMBinaryUtil.readstring(f)
    header_size += ICMBinaryUtil.words(@name) + ICMBinaryUtil.words(@desc)
    @non_blob_attributes = []
    non_blob_attribute_count.times do
      tmp = ICMBinaryAttributes.new
      header_size += tmp.init(f)
      @non_blob_attributes << tmp
    end
    @float_blob_attributes = []
    float_blob_attributes_count.times do
      tmp = ICMBinaryAttributes.new
      header_size += tmp.init(f)
      @float_blob_attributes << tmp
    end
    @double_blob_attributes = []
    double_blob_attributes_count.times do
      tmp = ICMBinaryAttributes.new
      header_size += tmp.init(f)
      @double_blob_attributes << tmp
    end
    @objects = []
    object_count.times do
      name = ICMBinaryUtil.readstring(f)
      header_size += ICMBinaryUtil.words(name)
      float_blob_for_obj = nil
      double_blob_for_obj = nil
      size_for_obj = non_blob_attribute_count
      if float_blob_attributes_count > 0
        float_blob_for_obj = []
        float_blob_attributes_count.times do
          v = ICMBinaryUtil.readlong(f)
          float_blob_for_obj << v
          header_size += 1
          size_for_obj += v
        end
      end
      if double_blob_attributes_count > 0
        double_blob_for_obj = []
        double_blob_attributes_count.times do
          v = ICMBinaryUtil.readlong(f)
          double_blob_for_obj << v
          header_size += 1
          size_for_obj += (v * 2)
        end
      end
      obj = ICMBinaryObject.new(name, object_offset, float_blob_for_obj, double_blob_for_obj)
      object_offset += size_for_obj
      @objects << obj
      @objectHash[name] = obj
    end
    [header_size, object_offset]
  end
  def get_object(name); @objectHash[name]; end
  def get_attribute_info(name)
    @non_blob_attributes.each_with_index { |a, i| return [i, 0] if a.name == name }
    @float_blob_attributes.each_with_index { |a, i| return [i, 1] if a.name == name }
    @double_blob_attributes.each_with_index { |a, i| return [i, 2] if a.name == name }
    nil
  end
  def get_non_blob_attribute_count; @non_blob_attributes.size; end
  def get_non_blob_attribute_name(n); @non_blob_attributes[n].name; end
  def get_non_blob_attribute_desc(n); @non_blob_attributes[n].desc; end
  def get_float_blob_attribute_count; @float_blob_attributes.size; end
  def get_float_blob_attribute_name(n); @float_blob_attributes[n].name; end
  def get_float_blob_attribute_desc(n); @float_blob_attributes[n].desc; end
  def get_double_blob_attribute_count; @double_blob_attributes.size; end
  def get_double_blob_attribute_name(n); @double_blob_attributes[n].name; end
  def get_double_blob_attribute_desc(n); @double_blob_attributes[n].desc; end
  def list_attributes
    @non_blob_attributes.each   { |a| puts "#{a.name} '#{a.desc}'" }
    @float_blob_attributes.each { |a| puts "#{a.name} '#{a.desc}' (blob)" }
    @double_blob_attributes.each{ |a| puts "#{a.name} '#{a.desc}' (double blob)" }
  end
  def list_objects; @objects.each { |o| puts o.name }; end
  def get_blob_sizes(name)
    obj = @objectHash[name]
    raise 'invalid object' if obj.nil?
    @float_blob_attributes.each_with_index { |a, i| puts "#{a.name} '#{a.desc}' #{obj.get_float_blob_size(i)}" }
    @double_blob_attributes.each_with_index { |a, i| puts "#{a.name} '#{a.desc}' #{obj.get_double_blob_size(i)}" }
  end
end

class ICMBinaryReader
  def init(binary_file, risk)
    raise ArgumentError, "Binary file not found: #{binary_file}" unless File.exist?(binary_file)
    @f = File.open(binary_file, 'rb')
    version = ICMBinaryUtil.readlong(@f)
    if version == 20151009
      @max = true
    elsif version == 20110922
      @max = false
    else
      puts 'invalid file type'
      return false
    end
    if @max
      @timestep_count = 1
    else
      @timestep_count = ICMBinaryUtil.readlong(@f)
      @timesteps = []
      @timestep_count.times do
        ts = risk ? ICMBinaryUtil.readdouble(@f) : ICMBinaryUtil.readdate(@f)
        @timesteps << ts
      end
    end
    table_count = ICMBinaryUtil.readlong(@f)
    skipped_words = ICMBinaryUtil.readlong(@f)
    found_words = 0
    tables = []
    @tables_hash = {}
    object_offset = 0
    table_count.times do
      table = ICMBinaryTable.new
      hs, oo = table.init(@f, @max, object_offset)
      found_words += hs
      object_offset = oo
      tables << table
      @tables_hash[table.name] = table
    end
    @timestep_size = object_offset
    @data_offset = found_words + 3
    @data_offset += 1 + (2 * @timestep_count) unless @max
    if skipped_words != found_words
      puts "expected #{skipped_words} found #{found_words}"
      return false
    end
    expected_file_size = ((@timestep_size * @timestep_count) + @data_offset) * 4
    actual_file_size = @f.size
    if expected_file_size != actual_file_size
      puts "expected file size = #{expected_file_size} found file size = #{actual_file_size}"
      return false
    end
    true
  end
  def timesteps; @timesteps.size; end
  def timestep(i); @timesteps[i]; end
  def get_table(name); @tables_hash[name]; end
  def get_value(timestep, table_name, object_id, attribute, index)
    raise 'invalid timestep' if timestep < 0 || timestep >= @timestep_count
    table = get_table(table_name); raise 'invalid table' if table.nil?
    object = table.get_object(object_id); raise 'invalid object' if object.nil?
    info = table.get_attribute_info(attribute); raise 'invalid attribute' if info.nil?
    if info[1] == 1
      bs = object.get_float_blob_size(info[0])
      return 'XXXXX' if index < 0 || index >= bs
      offset = @data_offset + (@timestep_size * timestep) + object.offset + object.get_float_blob_offset(info[0]) + index + table.get_non_blob_attribute_count
    elsif info[1] == 2
      bs = object.get_double_blob_size(info[0])
      return 'XXXXX' if index < 0 || index >= bs
      offset = @data_offset + (@timestep_size * timestep) + object.offset + object.get_double_blob_offset(info[0]) + (index * 2) + table.get_non_blob_attribute_count
    else
      raise 'non zero index for non blob attribute' if index != 0
      offset = @data_offset + (@timestep_size * timestep) + (object.offset + info[0])
    end
    @f.seek(offset * 4, IO::SEEK_SET)
    info[1] == 2 ? @f.read(8).unpack1('d') : @f.read(4).unpack1('f')
  end
  def get_results(obj_type, id, attribute)
    (0...@timesteps.size).each { |i| puts "#{@timesteps[i]},#{get_value(i, obj_type, id, attribute, 0)}" }
  end
  def get_all_results(obj_type, id)
    table = get_table(obj_type); raise 'invalid table' if table.nil?
    l = ''; l2 = ''
    table.get_non_blob_attribute_count.times do |i|
      l += ',' + table.get_non_blob_attribute_name(i)
      l2 += ',' + table.get_non_blob_attribute_desc(i)
    end
    puts l; puts l2
    if @timesteps.nil?
      l = ''
      table.get_non_blob_attribute_count.times { |j| l += ',' + get_value(0, obj_type, id, table.get_non_blob_attribute_name(j), 0).to_s }
      puts l
    else
      (0...@timesteps.size).each do |i|
        l = "#{@timesteps[i]}"
        table.get_non_blob_attribute_count.times { |j| l += ',' + get_value(i, obj_type, id, table.get_non_blob_attribute_name(j), 0).to_s }
        puts l
      end
    end
  end
  def get_blob_sizes(obj_type, id)
    table = get_table(obj_type); raise 'invalid table' if table.nil?
    table.get_blob_sizes(id)
  end
  def get_all_blob_results(obj_type, id, index)
    table = get_table(obj_type); raise 'invalid table' if table.nil?
    l = ''; l2 = ''
    table.get_float_blob_attribute_count.times { |i| l += ',' + table.get_float_blob_attribute_name(i); l2 += ',' + table.get_float_blob_attribute_desc(i) }
    table.get_double_blob_attribute_count.times{ |i| l += ',' + table.get_double_blob_attribute_name(i); l2 += ',' + table.get_double_blob_attribute_desc(i) }
    puts l; puts l2
    if @timesteps.nil?
      l = ''
      table.get_float_blob_attribute_count.times { |j| l += ',' + get_value(0, obj_type, id, table.get_float_blob_attribute_name(j), index).to_s }
      table.get_double_blob_attribute_count.times{ |j| l += ',' + get_value(0, obj_type, id, table.get_double_blob_attribute_name(j), index).to_s }
      puts l
    else
      (0...@timesteps.size).each do |i|
        l = "#{@timesteps[i]}"
        table.get_float_blob_attribute_count.times { |j| l += ',' + get_value(i, obj_type, id, table.get_float_blob_attribute_name(j), index).to_s }
        table.get_double_blob_attribute_count.times{ |j| l += ',' + get_value(i, obj_type, id, table.get_double_blob_attribute_name(j), index).to_s }
        puts l
      end
    end
  end
  def list_tables; @tables_hash.keys.sort.each { |k| puts k }; end
  def list_attributes(obj_type); t = get_table(obj_type); raise 'invalid table' if t.nil?; t.list_attributes; end
  def list_objects(obj_type); t = get_table(obj_type); raise 'invalid table' if t.nil?; t.list_objects; end
  def close!; @f&.close unless @f.nil? || @f.closed?; end
end

if $PROGRAM_NAME == __FILE__ || (defined?(ARGV) && !ARGV.empty?)
  begin
    usage = false
    if ARGV.count < 2
      usage = true
    else
      icmbr = ICMBinaryReader.new
      if !icmbr.init(ARGV[0], ARGV[1] == 'RR')
        puts 'failed to initialise'
      else
        if    ARGV.count == 2 && ARGV[1] == 'T'
          icmbr.list_tables
        elsif ARGV.count == 3 && ARGV[1] == 'A'
          icmbr.list_attributes(ARGV[2])
        elsif ARGV.count == 3 && ARGV[1] == 'O'
          icmbr.list_objects(ARGV[2])
        elsif ARGV.count == 4 && (ARGV[1] == 'R' || ARGV[1] == 'RR')
          icmbr.get_all_results ARGV[2], ARGV[3]
        elsif ARGV.count == 4 && ARGV[1] == 'S'
          icmbr.get_blob_sizes ARGV[2], ARGV[3]
        elsif ARGV.count == 5 && ARGV[1] == 'BR'
          icmbr.get_all_blob_results ARGV[2], ARGV[3], ARGV[4].to_i
        else
          usage = true
        end
      end
    end
    if usage
      puts 'usage - <filename> T = lists tables'
      puts '        <filename> A <table>'
      puts '        <filename> O <table>'
      puts '        <filename> R  <table> <object>'
      puts '        <filename> RR <table> <object>  (risk)'
      puts '        <filename> S  <table> <object>'
      puts '        <filename> BR <table> <object> <index>'
    end
  rescue StandardError => e
    fix_log "Aborted: #{e.message}"
  ensure
    icmbr&.close!
  end
end
