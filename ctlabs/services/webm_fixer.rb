# -----------------------------------------------------------------------------
# File        : ctlabs/services/webm_fixer.rb
# Description : Pure-Ruby EBML/WebM post-processor that adds Duration, SeekHead,
#               Cues, and exact Segment/Cluster sizes to MediaRecorder WebM files
#               so Firefox (Gecko) and other browsers can seek cleanly.
# License     : MIT License
# -----------------------------------------------------------------------------

require 'set'

class WebmFixer
  @mutex = Mutex.new

  EBML_ID       = 0x1a45dfa3
  SEGMENT_ID    = 0x18538067
  SEEKHEAD_ID   = 0x114d9b74
  SEEK_ID       = 0x4dbb
  SEEK_ID_EL    = 0x53ab
  SEEK_POS_EL   = 0x53ac
  INFO_ID       = 0x1549a966
  TIMECODE_SCALE_ID = 0x2ad7b1
  DURATION_ID   = 0x4489
  TRACKS_ID     = 0x1654ae6b
  TRACK_ENTRY_ID = 0xae
  TRACK_NUM_ID  = 0xd7
  TRACK_TYPE_ID = 0x83
  CLUSTER_ID    = 0x1f43b675
  TIMECODE_ID   = 0xe7
  SIMPLE_BLOCK_ID = 0xa3
  BLOCK_GROUP_ID  = 0xa0
  CUES_ID       = 0x1c53bb6b
  CUE_POINT_ID  = 0xbb
  CUE_TIME_ID   = 0xb3
  CUE_TRACK_POS_ID = 0xb7
  CUE_TRACK_ID  = 0xf7
  CUE_CLUSTER_POS_ID = 0xf1

  TOP_LEVEL_PREFIXES = [
    [0x1f, 0x43, 0xb6, 0x75].pack('C*').b, # Cluster
    [0x1c, 0x53, 0xbb, 0x6b].pack('C*').b, # Cues
    [0x15, 0x49, 0xa9, 0x66].pack('C*').b, # Info
    [0x16, 0x54, 0xae, 0x6b].pack('C*').b, # Tracks
    [0x11, 0x4d, 0x9b, 0x74].pack('C*').b, # SeekHead
    [0x12, 0x54, 0xc3, 0x67].pack('C*').b, # Tags
    [0x10, 0x43, 0xa7, 0x70].pack('C*').b  # Chapters
  ].freeze

  UNKNOWN_VINT_8 = [0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff].pack('C*').b

  def self.needs_fix?(path)
    return false unless path && File.file?(path) && path.downcase.end_with?('.webm')

    size = File.size(path)
    return false if size < 64

    head = File.binread(path, [size, 4096].min)
    seg_idx = head.index([0x18, 0x53, 0x80, 0x67].pack('C*').b)
    return false unless seg_idx

    # Unknown Segment size (01ffffffffffffff)
    return true if head.byteslice(seg_idx + 4, 8) == UNKNOWN_VINT_8

    # Also check if Cues is missing in both head and tail
    cues_sig = [0x1c, 0x53, 0xbb, 0x6b].pack('C*').b
    return false if head.include?(cues_sig)

    tail_len = [size, 16_384].min
    tail = IO.binread(path, tail_len, size - tail_len)
    !tail.include?(cues_sig)
  rescue StandardError
    false
  end

  def self.ensure_seekable(path)
    return false unless needs_fix?(path)

    @mutex.synchronize do
      return false unless needs_fix?(path)

      data = File.binread(path)
      fixed = fix_bytes(data)
      return false unless fixed && fixed.bytesize > 64

      tmp = "#{path}.tmp.#{Process.pid}.#{Thread.current.object_id}"
      File.binwrite(tmp, fixed)
      File.rename(tmp, path)
      true
    end
  rescue StandardError => e
    warn "[WebmFixer] Failed to fix #{path}: #{e.message}"
    false
  end

  def self.fix_bytes(data)
    pos = 0
    ebml_id, l1 = read_vint(data, pos, true)
    return nil unless ebml_id == EBML_ID

    ebml_len, l2 = read_vint(data, pos + l1, false)
    ebml_end = pos + l1 + l2 + ebml_len
    ebml_header = data.byteslice(0, ebml_end)

    pos = ebml_end
    seg_id, sl1 = read_vint(data, pos, true)
    return nil unless seg_id == SEGMENT_ID

    _seg_len, sl2 = read_vint(data, pos + sl1, false)
    pos += sl1 + sl2

    info_body = nil
    tracks_body = nil
    clusters = []

    while pos < data.bytesize
      eid, el1 = read_vint(data, pos, true)
      elen, el2 = read_vint(data, pos + el1, false)
      edata = pos + el1 + el2
      unknown_len = (elen == (1 << (7 * el2)) - 1)

      if eid == CLUSTER_ID
        if unknown_len
          epos = edata
          tc = 0
          max_rel = 0
          kf_tracks = Set.new
          while epos < data.bytesize
            prefix = data.byteslice(epos, 4)
            break if TOP_LEVEL_PREFIXES.include?(prefix)

            cid, cl1 = read_vint(data, epos, true)
            clen, cl2 = read_vint(data, epos + cl1, false)
            cdata = epos + cl1 + cl2
            if cid == TIMECODE_ID
              tc = read_uint(data, cdata, clen)
            elsif cid == SIMPLE_BLOCK_ID && clen >= 4
              tnum, tl = read_vint(data, cdata, false)
              rel = data.byteslice(cdata + tl, 2).unpack1('s>')
              flags = data.getbyte(cdata + tl + 2)
              max_rel = rel if rel > max_rel
              kf_tracks << tnum if (flags & 0x80) != 0
            end
            epos = cdata + clen
          end
          clusters << {
            body: data.byteslice(edata, epos - edata),
            tc: tc,
            max_rel: max_rel,
            kf_tracks: kf_tracks
          }
          pos = epos
        else
          body = data.byteslice(edata, elen)
          tc, max_rel, kf_tracks = scan_cluster_body(body)
          clusters << {
            body: body,
            tc: tc,
            max_rel: max_rel,
            kf_tracks: kf_tracks
          }
          pos = edata + elen
        end
      elsif eid == INFO_ID
        info_body = data.byteslice(edata, elen)
        pos = edata + elen
      elsif eid == TRACKS_ID
        tracks_body = data.byteslice(edata, elen)
        pos = edata + elen
      elsif eid == SEEKHEAD_ID || eid == CUES_ID
        pos = edata + elen
      else
        pos = edata + elen
      end
    end

    return nil unless info_body && tracks_body && !clusters.empty?

    video_track = find_video_track(tracks_body) || 1
    last_c = clusters.last
    total_dur_units = [last_c[:tc] + last_c[:max_rel] + 33, 1].max.to_f

    new_info_body = update_info_duration(info_body, total_dur_units)
    info_el = make_element(INFO_ID, new_info_body)
    tracks_el = make_element(TRACKS_ID, tracks_body)

    # Fixed-size SeekHead template so offsets are 100% deterministic
    # 3 entries: Info, Tracks, Cues (each Seek entry uses 8-byte SeekPosition)
    dummy_seek_head = build_seek_head(0, 0, 0)
    sh_size = dummy_seek_head.bytesize

    info_offset = sh_size
    tracks_offset = info_offset + info_el.bytesize
    cur_offset = tracks_offset + tracks_el.bytesize

    cluster_els = []
    cue_entries = []

    clusters.each_with_index do |cl, idx|
      c_el = make_element_vint8(CLUSTER_ID, cl[:body])
      if cl[:kf_tracks].include?(video_track) || idx == 0
        cue_entries << { time: cl[:tc], track: video_track, pos: cur_offset }
      end
      cluster_els << c_el
      cur_offset += c_el.bytesize
    end

    cues_offset = cur_offset
    cues_el = build_cues(cue_entries)
    seek_head_el = build_seek_head(info_offset, tracks_offset, cues_offset)

    seg_body_size = seek_head_el.bytesize + info_el.bytesize + tracks_el.bytesize +
                    cluster_els.sum(&:bytesize) + cues_el.bytesize

    out = ''.b
    out << ebml_header
    out << encode_id(SEGMENT_ID)
    out << encode_vint8(seg_body_size)
    out << seek_head_el
    out << info_el
    out << tracks_el
    cluster_els.each { |el| out << el }
    out << cues_el
    out
  end

  def self.scan_cluster_body(body)
    pos = 0
    tc = 0
    max_rel = 0
    kf_tracks = Set.new
    while pos < body.bytesize
      cid, cl1 = read_vint(body, pos, true)
      clen, cl2 = read_vint(body, pos + cl1, false)
      cdata = pos + cl1 + cl2
      if cid == TIMECODE_ID
        tc = read_uint(body, cdata, clen)
      elsif cid == SIMPLE_BLOCK_ID && clen >= 4
        tnum, tl = read_vint(body, cdata, false)
        rel = body.byteslice(cdata + tl, 2).unpack1('s>')
        flags = body.getbyte(cdata + tl + 2)
        max_rel = rel if rel > max_rel
        kf_tracks << tnum if (flags & 0x80) != 0
      end
      pos = cdata + clen
    end
    [tc, max_rel, kf_tracks]
  end

  def self.find_video_track(tracks_body)
    pos = 0
    while pos < tracks_body.bytesize
      eid, l1 = read_vint(tracks_body, pos, true)
      elen, l2 = read_vint(tracks_body, pos + l1, false)
      edata = pos + l1 + l2
      if eid == TRACK_ENTRY_ID
        ep = edata
        eend = edata + elen
        tnum = nil
        ttype = nil
        while ep < eend
          sub_id, sl1 = read_vint(tracks_body, ep, true)
          sub_len, sl2 = read_vint(tracks_body, ep + sl1, false)
          sdata = ep + sl1 + sl2
          tnum = read_uint(tracks_body, sdata, sub_len) if sub_id == TRACK_NUM_ID
          ttype = read_uint(tracks_body, sdata, sub_len) if sub_id == TRACK_TYPE_ID
          ep = sdata + sub_len
        end
        return tnum if ttype == 1 && tnum
      end
      pos = edata + elen
    end
    nil
  end

  def self.update_info_duration(info_body, dur_float)
    out = ''.b
    pos = 0
    has_dur = false
    while pos < info_body.bytesize
      eid, l1 = read_vint(info_body, pos, true)
      elen, l2 = read_vint(info_body, pos + l1, false)
      edata = pos + l1 + l2
      if eid == DURATION_ID
        out << make_element(DURATION_ID, [dur_float].pack('G'))
        has_dur = true
      else
        out << info_body.byteslice(pos, l1 + l2 + elen)
      end
      pos = edata + elen
    end
    out << make_element(DURATION_ID, [dur_float].pack('G')) unless has_dur
    out
  end

  def self.build_seek_head(info_pos, tracks_pos, cues_pos)
    entries = [
      [INFO_ID, info_pos],
      [TRACKS_ID, tracks_pos],
      [CUES_ID, cues_pos]
    ]
    body = ''.b
    entries.each do |id, offset|
      seek_body = make_element(SEEK_ID_EL, encode_id(id)) +
                  make_element(SEEK_POS_EL, [offset].pack('Q>'))
      body << make_element(SEEK_ID, seek_body)
    end
    make_element(SEEKHEAD_ID, body)
  end

  def self.build_cues(cue_entries)
    body = ''.b
    cue_entries.each do |entry|
      tp = make_element(CUE_TRACK_ID, encode_uint(entry[:track])) +
           make_element(CUE_CLUSTER_POS_ID, encode_uint(entry[:pos]))
      cp = make_element(CUE_TIME_ID, encode_uint(entry[:time])) +
           make_element(CUE_TRACK_POS_ID, tp)
      body << make_element(CUE_POINT_ID, cp)
    end
    make_element(CUES_ID, body)
  end

  def self.read_vint(data, pos, keep_marker = false)
    b = data.getbyte(pos)
    raise "EOF reading VINT at #{pos}" unless b

    len = 1
    mask = 0x80
    while len <= 8 && (b & mask) == 0
      len += 1
      mask >>= 1
    end
    raise "Invalid VINT at #{pos}" if len > 8

    val = keep_marker ? b : (b & ~mask)
    (1...len).each do |i|
      nb = data.getbyte(pos + i)
      raise "Truncated VINT at #{pos + i}" unless nb

      val = (val << 8) | nb
    end
    [val, len]
  end

  def self.read_uint(data, pos, len)
    val = 0
    len.times do |i|
      val = (val << 8) | data.getbyte(pos + i)
    end
    val
  end

  def self.encode_id(id)
    bytes = []
    v = id
    while v > 0
      bytes.unshift(v & 0xff)
      v >>= 8
    end
    bytes.pack('C*').b
  end

  def self.encode_uint(val)
    return "\x00".b if val == 0

    bytes = []
    v = val
    while v > 0
      bytes.unshift(v & 0xff)
      v >>= 8
    end
    bytes.pack('C*').b
  end

  def self.encode_vint(len)
    1.upto(8) do |width|
      max_val = (1 << (7 * width)) - 2
      next if len > max_val

      marker = 1 << (7 * width)
      val = marker | len
      bytes = []
      width.times do
        bytes.unshift(val & 0xff)
        val >>= 8
      end
      return bytes.pack('C*').b
    end
    encode_vint8(len)
  end

  def self.encode_vint8(len)
    val = (1 << 56) | len
    [val].pack('Q>')
  end

  def self.make_element(id, body)
    encode_id(id) + encode_vint(body.bytesize) + body
  end

  def self.make_element_vint8(id, body)
    encode_id(id) + encode_vint8(body.bytesize) + body
  end
end
