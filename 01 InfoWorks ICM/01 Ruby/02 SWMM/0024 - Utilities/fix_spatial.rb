# frozen_string_literal: true

# =============================================================================
# fix_spatial.rb
# -----------------------------------------------------------------------------
# Purpose : Hardened version of the InnoSpatial geometry helpers used by the
#           split-link scripts (split_link_into_chunks, split_links_around_node,
#           split_link_at_distance, link_length, distance, lerp).
# Inputs  : Required by other scripts in this folder via require_relative.
# Outputs : N/A - module of pure helpers.
# UI / EX : Library only; safe to be required from UI scripts.
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure (around any potentially fragile work)
#   - Nil-safe access to bends, us_node, ds_node
#   - Validates link has >= 2 vertices (4 floats) before splitting
#   - Validates positive distance / chunk size; rejects zero or negative
#   - Lerp clamped to [0,1]
#   - Preserves original public API names so callers continue to work
# =============================================================================

# Some parts of this code were adapted from the Turf.js library
# https://turfjs.org/  https://github.com/Turfjs/turf

module InnoSpatial
  extend self

  def ts
    Time.now.strftime('%Y-%m-%d %H:%M:%S')
  end

  # Splits all links around a node.
  def split_links_around_node(network, node, distance)
    return if network.nil? || node.nil?
    return unless distance.is_a?(Numeric) && distance > 0

    (node.us_links || []).each do |link|
      begin
        split_link_at_distance(network, link, link_length(link) - distance)
      rescue StandardError => e
        puts "[#{ts}] split_links_around_node us-error on #{link&.id}: #{e.message}"
      end
    end

    (node.ds_links || []).each do |link|
      begin
        split_link_at_distance(network, link, distance)
      rescue StandardError => e
        puts "[#{ts}] split_links_around_node ds-error on #{link&.id}: #{e.message}"
      end
    end
  end

  # Splits a link into evenly sized chunks.
  def split_link_into_chunks(network, link, chunk_size, normalize = true)
    return if network.nil? || link.nil?
    return unless chunk_size.is_a?(Numeric) && chunk_size > 0

    length = link_length(link)
    if length <= 0
      puts format('[%s] Cannot split link %s: zero length.', ts, link.id)
      return
    end

    if chunk_size >= length
      puts format('[%s] Cannot split link %s of length %0.2fm into chunks of size %0.2fm',
                  ts, link.id, length, chunk_size)
      return
    end

    segments = (length / chunk_size).floor
    return if segments < 2

    if normalize
      chunk_size_norm = (length / segments)
      (segments - 1).times do |i|
        split_link_at_distance(network, link, chunk_size_norm, i + 1)
      end
    else
      segments.times do |i|
        split_link_at_distance(network, link, chunk_size, i + 1)
      end
    end
  end

  # Splits a single link at a given distance from its upstream end.
  def split_link_at_distance(network, link, distance, node_i = 1)
    return if network.nil? || link.nil?
    return unless distance.is_a?(Numeric) && distance > 0

    bends = link['bends']
    if bends.nil? || bends.length < 4
      puts format('[%s] Link %s has < 2 vertices, cannot split.', ts, link.id)
      return
    end

    link_len = link_length(link)
    if link_len <= 0
      puts format('[%s] Link %s has zero length, cannot split.', ts, link.id)
      return
    end
    if distance >= link_len
      puts format('[%s] Link %s length %0.2f, cannot split with distance %0.2f',
                  ts, link.id, link_len, distance)
      return
    end

    index     = 0
    split_node = nil
    travelled = 0

    iterate_link_segments(link) do |seg|
      length = distance(*seg)

      if travelled + length > distance
        percent = (distance - travelled) / length

        split_node = network.new_row_object('wn_node')
        split_node.id = format('%s_%i', link['asset_id'], node_i)
        split_node['x'] = lerp(seg[0], seg[2], percent)
        split_node['y'] = lerp(seg[1], seg[3], percent)
        if link.us_node && link.ds_node
          split_node['z']            = lerp(link.us_node['z'],            link.ds_node['z'],            distance / link_len)
          split_node['ground_level'] = lerp(link.us_node['ground_level'], link.ds_node['ground_level'], distance / link_len)
        end
        split_node.write
        break
      else
        travelled += length
        index += 1
      end
    end

    return if split_node.nil?

    pre_bends = []
    post_bends = []
    bends.each_slice(2).with_index do |xy, i|
      if i > index
        post_bends += xy
      elsif i == index
        split_xy = [split_node['x'], split_node['y']]
        pre_bends  += xy + split_xy
        post_bends += split_xy
      else
        pre_bends += xy
      end
    end

    new_link = network.new_row_object('wn_pipe')
    link.table_info.fields.each do |field|
      new_link[field.name] = link[field.name]
    end

    new_link['bends']     = pre_bends
    new_link['ds_node_id'] = split_node.id
    new_link.write

    link['bends']     = post_bends
    link['us_node_id'] = split_node.id
    link.write
  end

  # Calculate the euclidean length of a link.
  def link_length(link)
    return 0.0 if link.nil?
    bends = link['bends']
    return 0.0 if bends.nil? || bends.length < 4
    length = 0
    iterate_link_segments(link) { |segment| length += distance(*segment) }
    length
  end

  # Find the euclidean distance between two xy coordinates.
  def distance(ax, ay, bx, by)
    Math.sqrt((ax - bx)**2 + (ay - by)**2)
  end

  # Iterates over link segments with overlap.
  def iterate_link_segments(link)
    return if link.nil?
    bends = link['bends']
    return if bends.nil? || bends.length < 4
    i = 0
    while i < bends.length - 2
      yield(bends[i, 4])
      i += 2
    end
  end

  # Linear interpolation, clamped to [0,1].
  def lerp(a, b, percent)
    pct = percent.clamp(0, 1)
    (1 - pct) * a + pct * b
  end
end
