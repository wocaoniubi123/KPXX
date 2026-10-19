// TS → MP4 remux（纯 Dart：只重打包，不解码）。
//
// 为什么需要它：iOS 的 AVFoundation 打不开"本地单独 .ts"（只认 HLS 里的 TS），
// 下载产物又是 HLS 拼接出来的 .ts ⇒ 离线播放报 "Cannot Open"。
// 这里把 MPEG-TS 里的 H.264 + AAC 重新封装成普通 MP4（非分片），iOS/桌面通用、零第三方依赖。
//
// 范围与取舍（都是有意为之）：
// · 只做 **H.264（stream_type 0x1B）+ AAC-ADTS（0x0F）**；H.265/AC-3/其它一律跳过；
//   两条轨都认不出来就抛错，只有一条也能出片（单轨 mp4）。
// · 不解码、不转码：视频 NAL 只是从 Annex-B（起始码）改成 AVCC（4 字节长度前缀）；
//   音频只去掉 ADTS 头（每帧 1024 samples），AAC 原始帧原样搬。
// · **两遍扫描**：第一遍建样本表（大小/时间戳/关键帧/SPS/PPS/ASC），第二遍边读边写 mdat。
//   100MB 的文件不会整体读进内存（每遍只按 188 字节 TS 包流式读）。
// · 断点/容错：TS 包错位自动重同步；CRC 不校验；未知 stream_type 跳过；遇到坏 ADTS 帧就丢。
// · 输出先写 `<mp4Path>.part`，成功才 rename；失败删 .part。

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// 转换失败（带一句人话原因）。管理器可以直接把 `toString()` 显示给用户。
class TsConvertException implements Exception {
  final String message;

  const TsConvertException(this.message);

  @override
  String toString() => 'TS→MP4 转换失败：$message';
}

/// 新接口：`TsToMp4.convert(tsPath: ..., mp4Path: ...)`。
class TsToMp4 {
  TsToMp4._();

  /// 把 [tsPath]（HLS 拼接产物，MPEG-TS）重封装成 [mp4Path]。
  ///
  /// 成功返回 [mp4Path]；失败抛 [TsConvertException]（输出 `.part` 会被删掉）。
  static Future<String> convert({
    required String tsPath,
    required String mp4Path,
  }) async {
    try {
      final ts = File(tsPath);
      if (!await ts.exists()) throw const TsConvertException('TS 文件不存在');
      final scan = await _scan(tsPath);
      if (!scan.hasAnything) {
        throw const TsConvertException('没找到可用的 H.264 / AAC 轨道');
      }
      await _writeMp4(tsPath: tsPath, mp4Path: mp4Path, scan: scan);
      return mp4Path;
    } on TsConvertException {
      rethrow;
    } catch (e) {
      // 解析里任何意外（越界/IO）都收敛成一种异常，调用方不必猜类型
      throw TsConvertException('$e');
    }
  }
}

// ===========================================================================
// 第一遍：扫 TS，建样本表
// ===========================================================================

class _Scan {
  final _VideoInfo? video;
  final _AudioInfo? audio;

  const _Scan(this.video, this.audio);

  bool get hasAnything =>
      (video != null && video!.samples.isNotEmpty) ||
      (audio != null && audio!.sizes.isNotEmpty);
}

class _VideoInfo {
  final Uint8List sps;
  final Uint8List pps;
  final int width;
  final int height;
  final List<_VideoSample> samples;

  const _VideoInfo({
    required this.sps,
    required this.pps,
    required this.width,
    required this.height,
    required this.samples,
  });
}

class _VideoSample {
  final int dts;
  final int pts;
  final int size; // AVCC 后的字节数（4 字节长度前缀 + NAL）
  final bool key; // 含 IDR（NAL type 5）

  const _VideoSample({
    required this.dts,
    required this.pts,
    required this.size,
    required this.key,
  });
}

class _AudioInfo {
  final int sampleRate;
  final int channels;
  final int objectType; // AAC-LC = 2
  final int freqIndex;
  final List<int> sizes; // 每帧去掉 ADTS 头后的字节数
  final List<int> durations; // 每帧的采样数（通常是 1024）

  const _AudioInfo({
    required this.sampleRate,
    required this.channels,
    required this.objectType,
    required this.freqIndex,
    required this.sizes,
    required this.durations,
  });
}

Future<_Scan> _scan(String tsPath) async {
  final videoSamples = <_VideoSample>[];
  Uint8List? sps;
  Uint8List? pps;
  var lastPts = 0;

  final adts = _AdtsParser();
  await _walkTs(tsPath, (kind, payload, pts, dts) async {
    if (kind == _TrackKind.video) {
      final nals = _splitAnnexB(payload);
      if (nals.isEmpty) return;
      final kept = <Uint8List>[];
      var key = false;
      for (final nal in nals) {
        if (nal.isEmpty) continue;
        final t = nal[0] & 0x1F;
        if (t == 7) {
          sps ??= nal;
          continue;
        }
        if (t == 8) {
          pps ??= nal;
          continue;
        }
        if (t == 5) key = true;
        kept.add(nal);
      }
      if (kept.isEmpty) return; // 纯 SPS/PPS 的配置 PES：不是一帧
      var size = 0;
      for (final n in kept) {
        size += 4 + n.length;
      }
      var p = pts;
      if (p < 0) p = lastPts + 3000; // 没带 PTS 的怪流：按 30fps 递推
      final d = dts < 0 ? p : dts;
      lastPts = p;
      videoSamples.add(_VideoSample(dts: d, pts: p, size: size, key: key));
    } else if (kind == _TrackKind.audio) {
      adts.feed(payload, collect: true, onFrame: (_, __) {});
    }
  });

  _VideoInfo? video;
  // 闭包里赋值的变量不会被流分析提升 ⇒ 先落成本地不可变引用再判空
  final spsOut = sps;
  final ppsOut = pps;
  if (videoSamples.isNotEmpty && spsOut != null && ppsOut != null) {
    final spsInfo = _parseSps(spsOut);
    video = _VideoInfo(
      sps: spsOut,
      pps: ppsOut,
      width: spsInfo?.width ?? 0,
      height: spsInfo?.height ?? 0,
      samples: videoSamples,
    );
  }

  _AudioInfo? audio;
  if (adts.hasFrames &&
      adts.sampleRate != null &&
      adts.channels != null &&
      adts.objectType != null &&
      adts.freqIndex != null) {
    audio = _AudioInfo(
      sampleRate: adts.sampleRate!,
      channels: adts.channels!,
      objectType: adts.objectType!,
      freqIndex: adts.freqIndex!,
      sizes: adts.sizes,
      durations: adts.durations,
    );
  }
  return _Scan(video, audio);
}

// ===========================================================================
// 第二遍：边读边写 mdat，再写 moov
// ===========================================================================

class _Chunk {
  final int offset;
  final int samples;

  const _Chunk(this.offset, this.samples);
}

class _Chunks {
  final List<_Chunk> video = <_Chunk>[];
  final List<_Chunk> audio = <_Chunk>[];
}

Future<void> _writeMp4({
  required String tsPath,
  required String mp4Path,
  required _Scan scan,
}) async {
  final video = scan.video;
  final audio = scan.audio;
  final videoInfo = video == null ? null : _videoTiming(video.samples);
  final videoBytes = videoInfo == null ? 0 : videoInfo.totalBytes; // 由 sizes 求和
  final audioBytes =
      audio == null ? 0 : audio.sizes.fold<int>(0, (s, v) => s + v);
  final dataBytes = videoBytes + audioBytes;

  final part = File('$mp4Path.part');
  try {
    if (await part.exists()) await part.delete();
    final out = await part.open(mode: FileMode.write);
    final chunks = _Chunks();
    var pos = 0;
    try {
      final ftyp = _buildFtyp();
      await out.writeFrom(ftyp);
      pos += ftyp.length;

      final mdatHeader = _buildMdatHeader(dataBytes);
      await out.writeFrom(mdatHeader);
      pos += mdatHeader.length;
      final dataStart = pos;

      // ---- 第二遍：按 TS 原始顺序写样本（视频/音频 chunk 交错，stco 记录真实偏移）----
      var vi = 0;
      var ai = 0;
      final adts = _AdtsParser();
      await _walkTs(tsPath, (kind, payload, pts, dts) async {
        if (kind == _TrackKind.video) {
          if (video == null) return;
          final nals = _splitAnnexB(payload);
          final kept = <Uint8List>[];
          for (final nal in nals) {
            if (nal.isEmpty) continue;
            final t = nal[0] & 0x1F;
            if (t == 7 || t == 8) continue; // SPS/PPS 已进 avcC
            kept.add(nal);
          }
          if (kept.isEmpty) return;
          final bb = BytesBuilder(copy: false);
          var size = 0;
          for (final n in kept) {
            bb.add(_u32(n.length));
            bb.add(n);
            size += 4 + n.length;
          }
          if (vi >= video.samples.length) {
            throw const TsConvertException('第二遍视频样本数超出第一遍（TS 不稳定）');
          }
          if (size != video.samples[vi].size) {
            throw TsConvertException(
                '视频样本 #$vi 大小不一致（第一遍 ${video.samples[vi].size} / 第二遍 $size）');
          }
          final bytes = bb.takeBytes();
          final off = pos;
          await out.writeFrom(bytes);
          pos += bytes.length;
          chunks.video.add(_Chunk(off, 1));
          vi++;
        } else if (kind == _TrackKind.audio) {
          if (audio == null) return;
          final frames = <Uint8List>[];
          adts.feed(payload, collect: false, onFrame: (f, _) => frames.add(f));
          if (frames.isEmpty) return;
          final off = pos;
          for (final f in frames) {
            if (ai >= audio.sizes.length) {
              throw const TsConvertException('第二遍音频帧数超出第一遍（TS 不稳定）');
            }
            if (f.length != audio.sizes[ai]) {
              throw TsConvertException(
                  '音频帧 #$ai 大小不一致（第一遍 ${audio.sizes[ai]} / 第二遍 ${f.length}）');
            }
            await out.writeFrom(f);
            pos += f.length;
            ai++;
          }
          chunks.audio.add(_Chunk(off, frames.length));
        }
      });

      if (video != null && vi != video.samples.length) {
        throw TsConvertException('视频样本数对不上（第一遍 ${video.samples.length} / 第二遍 $vi）');
      }
      if (audio != null && ai != audio.sizes.length) {
        throw TsConvertException('音频帧数对不上（第一遍 ${audio.sizes.length} / 第二遍 $ai）');
      }
      if (pos - dataStart != dataBytes) {
        throw TsConvertException(
            'mdat 写入字节不符（应为 $dataBytes，实际 ${pos - dataStart}）');
      }

      // moov 放 mdat 之后；所有偏移/大小此时已知
      final moov = _buildMoov(scan, videoInfo, chunks);
      await out.writeFrom(moov);
      pos += moov.length;
      await out.flush();
    } finally {
      await out.close();
    }

    if (await File(mp4Path).exists()) await File(mp4Path).delete();
    await part.rename(mp4Path);
  } catch (e) {
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
    rethrow;
  }
}

// ===========================================================================
// TS 解包
// ===========================================================================

enum _TrackKind { video, audio }

typedef _PesCallback = Future<void> Function(
    _TrackKind kind, Uint8List payload, int pts, int dts);

Future<void> _walkTs(String path, _PesCallback onPes) async {
  final raf = await File(path).open();
  try {
    final sections = <int, _SectionAssembler>{};
    int? pmtPid;
    int? videoPid;
    int? audioPid;
    final pending = <int, _PendingPes>{};

    Future<void> flush(int? pid) async {
      if (pid == null) return;
      final p = pending.remove(pid);
      if (p == null || p.data.isEmpty) return;
      final kind = pid == videoPid
          ? _TrackKind.video
          : (pid == audioPid ? _TrackKind.audio : null);
      if (kind == null) return;
      await onPes(kind, p.data.takeBytes(), p.pts, p.dts);
    }

    var buffer = Uint8List(0);
    var aligned = false;

    while (true) {
      final chunk = await raf.read(188 * 1024);
      final eof = chunk.isEmpty;
      if (!eof) {
        buffer = buffer.isEmpty
            ? chunk
            : Uint8List.fromList(<int>[...buffer, ...chunk]);
      } else if (buffer.isEmpty) {
        break;
      }

      var off = 0;
      if (!aligned) {
        final sync = _findSync(buffer, 0);
        if (sync < 0) {
          buffer = buffer.length > 187
              ? Uint8List.fromList(buffer.sublist(buffer.length - 187))
              : buffer;
          if (eof) break;
          continue;
        }
        off = sync;
        aligned = true;
      }

      while (off + 188 <= buffer.length) {
        if (buffer[off] != 0x47) {
          final sync = _findSync(buffer, off + 1);
          if (sync < 0) {
            off = buffer.length;
            break;
          }
          off = sync;
          continue;
        }
        final b1 = buffer[off + 1];
        final b2 = buffer[off + 2];
        final b3 = buffer[off + 3];
        final pusi = (b1 & 0x40) != 0;
        final pid = ((b1 & 0x1F) << 8) | b2;
        final afc = (b3 >> 4) & 0x03;
        var p = off + 4;
        if (afc == 2 || afc == 3) {
          final afl = buffer[p];
          p += 1 + afl;
        }
        if ((afc == 1 || afc == 3) && p < off + 188) {
          final payload = Uint8List.sublistView(buffer, p, off + 188);
          if (pid == 0 || (pmtPid != null && pid == pmtPid)) {
            final asm = sections.putIfAbsent(pid, _SectionAssembler.new);
            asm.feed(payload, pusi, (section) {
              if (pid == 0) {
                final pmt = _parsePat(section);
                if (pmt != null) pmtPid = pmt;
              } else {
                final es = _parsePmt(section);
                videoPid ??= es.$1;
                audioPid ??= es.$2;
              }
            });
          } else if (pid == videoPid || pid == audioPid) {
            if (pusi) {
              await flush(pid);
              final h = _parsePesHeader(payload);
              if (h != null) {
                final pp = _PendingPes(h.pts, h.dts, h.payloadLength);
                pp.add(Uint8List.sublistView(payload, h.payloadOffset));
                pending[pid] = pp;
              }
            } else {
              pending[pid]?.add(payload);
            }
          }
        }
        off += 188;
      }
      buffer = off < buffer.length
          ? Uint8List.fromList(buffer.sublist(off))
          : Uint8List(0);
      if (eof) break;
    }
    await flush(videoPid);
    await flush(audioPid);
  } finally {
    await raf.close();
  }
}

/// 找同步头：要求 `b[i]==0x47` 且下一包也是 `0x47`（容忍末尾不足一包的情况）
int _findSync(Uint8List b, int start) {
  for (var i = start; i + 188 < b.length; i++) {
    if (b[i] == 0x47 && b[i + 188] == 0x47) return i;
  }
  for (var i = start; i < b.length; i++) {
    if (b[i] == 0x47 && i + 188 >= b.length) return i;
  }
  return -1;
}

class _PendingPes {
  final int pts;
  final int dts;

  /// 剩余可收字节；-1 = 不限（视频 PES 常见 packet_length=0）
  int remaining;
  final BytesBuilder data = BytesBuilder(copy: false);

  _PendingPes(this.pts, this.dts, this.remaining);

  void add(Uint8List d) {
    if (d.isEmpty || remaining == 0) return;
    if (remaining < 0 || d.length <= remaining) {
      data.add(d);
      if (remaining > 0) remaining -= d.length;
    } else {
      data.add(Uint8List.sublistView(d, 0, remaining));
      remaining = 0;
    }
  }
}

class _PesHeader {
  final int pts;
  final int dts;
  final int payloadOffset;
  final int payloadLength;

  const _PesHeader(this.pts, this.dts, this.payloadOffset, this.payloadLength);
}

_PesHeader? _parsePesHeader(Uint8List p) {
  if (p.length < 9) return null;
  if (p[0] != 0 || p[1] != 0 || p[2] != 1) return null;
  final packetLength = (p[4] << 8) | p[5];
  final flags = p[7];
  final headerLen = p[8];
  final payloadOffset = 9 + headerLen;
  final payloadLength = packetLength == 0 ? -1 : packetLength - 3 - headerLen;
  if (payloadLength < -1) return null;
  if (payloadOffset > p.length) return null;
  final ptsDts = (flags >> 6) & 0x03;
  var pts = -1;
  var dts = -1;
  if (ptsDts >= 2 && p.length >= 14) pts = _readTs33(p, 9);
  if (ptsDts == 3 && p.length >= 19) dts = _readTs33(p, 14);
  return _PesHeader(pts, dts, payloadOffset, payloadLength);
}

int _readTs33(Uint8List p, int o) {
  return ((p[o] >> 1) & 0x07) << 30 |
      (p[o + 1] << 22) |
      ((p[o + 2] >> 1) & 0x7F) << 15 |
      (p[o + 3] << 7) |
      ((p[o + 4] >> 1) & 0x7F);
}

class _SectionAssembler {
  Uint8List? _data;
  int _need = 0;
  int _filled = 0;

  void feed(Uint8List payload, bool pusi, void Function(Uint8List) onSection) {
    var off = 0;
    if (pusi) {
      if (payload.isEmpty) return;
      off = 1 + payload[0];
      _data = null;
      _need = 0;
      _filled = 0;
    }
    while (off < payload.length) {
      if (_data == null) {
        if (payload[off] == 0xFF) return; // stuffing
        if (payload.length - off < 3) return;
        final len = ((payload[off + 1] & 0x0F) << 8) | payload[off + 2];
        _need = 3 + len;
        if (_need < 4 || _need > 4096) return;
        _data = Uint8List(_need);
        _filled = 0;
      }
      final take = math.min(_need - _filled, payload.length - off);
      _data!.setRange(_filled, _filled + take, payload, off);
      _filled += take;
      off += take;
      if (_filled == _need) {
        final section = _data!;
        _data = null;
        _need = 0;
        _filled = 0;
        onSection(section);
      } else {
        return; // 等下一个 TS 包
      }
    }
  }
}

/// PAT → 第一个 program 的 PMT PID（多 program 只看第一个）
int? _parsePat(Uint8List s) {
  if (s.length < 12 || s[0] != 0x00) return null;
  final len = ((s[1] & 0x0F) << 8) | s[2];
  final end = math.min(3 + len - 4, s.length); // 去掉 CRC
  for (var i = 8; i + 4 <= end; i += 4) {
    final program = (s[i] << 8) | s[i + 1];
    final pid = ((s[i + 2] & 0x1F) << 8) | s[i + 3];
    if (program != 0) return pid;
  }
  return null;
}

/// PMT → (h264 pid, aac pid)
(int?, int?) _parsePmt(Uint8List s) {
  if (s.length < 16 || s[0] != 0x02) return (null, null);
  final len = ((s[1] & 0x0F) << 8) | s[2];
  final end = math.min(3 + len - 4, s.length);
  final programInfoLen = ((s[10] & 0x0F) << 8) | s[11];
  var i = 12 + programInfoLen;
  int? video;
  int? audio;
  while (i + 5 <= end) {
    final type = s[i];
    final pid = ((s[i + 1] & 0x1F) << 8) | s[i + 2];
    final esInfoLen = ((s[i + 3] & 0x0F) << 8) | s[i + 4];
    if (type == 0x1B) video ??= pid;
    if (type == 0x0F) audio ??= pid;
    i += 5 + esInfoLen;
  }
  return (video, audio);
}

// ===========================================================================
// H.264 Annex-B / SPS
// ===========================================================================

/// 把 PES payload 按起始码拆成 NAL（去掉起始码与尾部的 `trailing_zero_8bits`）
List<Uint8List> _splitAnnexB(Uint8List d) {
  final starts = <int>[];
  final codeLens = <int>[];
  var i = 0;
  while (i + 3 <= d.length) {
    if (d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1) {
      starts.add(i);
      codeLens.add(3);
      i += 3;
    } else if (i + 4 <= d.length &&
        d[i] == 0 &&
        d[i + 1] == 0 &&
        d[i + 2] == 0 &&
        d[i + 3] == 1) {
      starts.add(i);
      codeLens.add(4);
      i += 4;
    } else {
      i++;
    }
  }
  final out = <Uint8List>[];
  for (var k = 0; k < starts.length; k++) {
    final begin = starts[k] + codeLens[k];
    final end = k + 1 < starts.length ? starts[k + 1] : d.length;
    if (end <= begin) continue;
    var e = end;
    while (e > begin && d[e - 1] == 0) {
      e--; // Annex-B 的 trailing_zero_8bits 不属于 NAL
    }
    if (e <= begin) continue;
    out.add(Uint8List.sublistView(d, begin, e));
  }
  return out;
}

class _SpsInfo {
  final int width;
  final int height;

  const _SpsInfo(this.width, this.height);
}

/// 最小 SPS 解析：只取宽高（avc1/tkhd 要显示尺寸）。解析失败返回 null（仍可出片，宽高 0）。
_SpsInfo? _parseSps(Uint8List nal) {
  try {
    if (nal.length < 4) return null;
    final profile = nal[1];
    final rbsp = _unescapeRbsp(Uint8List.sublistView(nal, 1));
    final br = _BitReader(rbsp);
    br.bits(8); // profile_idc
    br.bits(8); // constraint flags
    br.bits(8); // level_idc
    br.ue(); // seq_parameter_set_id
    var chromaFormat = 1;
    const highProfiles = <int>{
      100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135
    };
    if (highProfiles.contains(profile)) {
      chromaFormat = br.ue();
      if (chromaFormat == 3) br.bits(1);
      br.ue(); // bit_depth_luma_minus8
      br.ue(); // bit_depth_chroma_minus8
      br.bits(1); // qpprime_y_zero_transform_bypass_flag
      if (br.bits(1) == 1) {
        // seq_scaling_matrix_present_flag：把 scaling list 的体积按规范跳过去
        final count = chromaFormat != 3 ? 8 : 12;
        for (var i = 0; i < count; i++) {
          final present = i < 6 ? br.bits(1) : br.bits(1);
          if (present == 1) {
            final size = i < 6 ? 16 : 64;
            var lastScale = 8;
            var nextScale = 8;
            for (var j = 0; j < size; j++) {
              if (nextScale != 0) {
                final delta = br.se();
                nextScale = (lastScale + delta + 256) % 256;
              }
              lastScale = nextScale == 0 ? lastScale : nextScale;
            }
          }
        }
      }
    }
    br.ue(); // log2_max_frame_num_minus4
    final pocType = br.ue();
    if (pocType == 0) {
      br.ue(); // log2_max_pic_order_cnt_lsb_minus4
    } else if (pocType == 1) {
      br.bits(1);
      br.se();
      br.se();
      final n = br.ue();
      for (var i = 0; i < n; i++) {
        br.se();
      }
    }
    br.ue(); // max_num_ref_frames
    br.bits(1); // gaps_in_frame_num_value_allowed_flag
    final widthMbs = br.ue() + 1;
    final heightMapUnits = br.ue() + 1;
    final frameMbsOnly = br.bits(1);
    if (frameMbsOnly == 0) br.bits(1); // mb_adaptive_frame_field_flag
    br.bits(1); // direct_8x8_inference_flag
    var cropL = 0, cropR = 0, cropT = 0, cropB = 0;
    if (br.bits(1) == 1) {
      cropL = br.ue();
      cropR = br.ue();
      cropT = br.ue();
      cropB = br.ue();
    }
    final chromaArrayType = chromaFormat;
    final cropUnitX = chromaArrayType == 0
        ? 1
        : (chromaArrayType == 3 ? 1 : 2);
    final cropUnitY = (chromaArrayType == 0
            ? 1
            : (chromaArrayType == 3 ? 1 : 2)) *
        (2 - frameMbsOnly);
    final width = widthMbs * 16 - (cropL + cropR) * cropUnitX;
    final height =
        (2 - frameMbsOnly) * heightMapUnits * 16 - (cropT + cropB) * cropUnitY;
    // 离谱值（解析错位/SPS 非标准）宁可不填尺寸，也别写出一个 6 万像素宽的 avc1
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384) {
      return null;
    }
    return _SpsInfo(width, height);
  } catch (_) {
    return null;
  }
}

/// 去掉 RBSP 的防竞争字节（00 00 03 → 00 00）
Uint8List _unescapeRbsp(Uint8List d) {
  final out = BytesBuilder(copy: false);
  var zeros = 0;
  for (var i = 0; i < d.length; i++) {
    final b = d[i];
    if (zeros >= 2 && b == 3) {
      zeros = 0;
      continue;
    }
    out.addByte(b);
    if (b == 0) {
      zeros++;
    } else {
      zeros = 0;
    }
  }
  return out.takeBytes();
}

class _BitReader {
  final Uint8List _d;
  int _pos = 0;

  _BitReader(this._d);

  int _bit() {
    if (_pos >= _d.length * 8) return 0;
    final v = (_d[_pos >> 3] >> (7 - (_pos & 7))) & 1;
    _pos++;
    return v;
  }

  int bits(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 1) | _bit();
    }
    return v;
  }

  int ue() {
    var zeros = 0;
    while (_bit() == 0) {
      zeros++;
      if (zeros > 31) return 0;
    }
    var v = 0;
    for (var i = 0; i < zeros; i++) {
      v = (v << 1) | _bit();
    }
    return (1 << zeros) - 1 + v;
  }

  int se() {
    final k = ue();
    return (k & 1) == 1 ? (k + 1) >> 1 : -(k >> 1);
  }
}

// ===========================================================================
// AAC ADTS
// ===========================================================================

class _AdtsParser {
  static const List<int> _rates = <int>[
    96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050,
    16000, 12000, 11025, 8000, 7350,
  ];

  final List<int> _buf = <int>[];
  final List<int> sizes = <int>[];
  final List<int> durations = <int>[];
  int? sampleRate;
  int? channels;
  int? objectType;
  int? freqIndex;
  bool _invalid = false;

  bool get hasFrames => sizes.isNotEmpty;

  void feed(
    Uint8List data, {
    required bool collect,
    required void Function(Uint8List frame, int duration) onFrame,
  }) {
    if (_invalid) return;
    _buf.addAll(data);
    while (_buf.length >= 7) {
      if (!(_buf[0] == 0xFF && (_buf[1] & 0xF6) == 0xF0)) {
        // 失步：找下一个 sync（找不到就把缓冲清掉，等下一段）
        var s = -1;
        for (var i = 1; i + 1 < _buf.length; i++) {
          if (_buf[i] == 0xFF && (_buf[i + 1] & 0xF6) == 0xF0) {
            s = i;
            break;
          }
        }
        if (s < 0) {
          _buf.clear();
          return;
        }
        _buf.removeRange(0, s);
        continue;
      }
      final protectionAbsent = _buf[1] & 1;
      final headerLen = protectionAbsent == 1 ? 7 : 9;
      if (_buf.length < headerLen) return;
      final profile = (_buf[2] >> 6) & 0x03;
      final sf = (_buf[2] >> 2) & 0x0F;
      final ch = ((_buf[2] & 1) << 2) | ((_buf[3] >> 6) & 0x03);
      final frameLen =
          ((_buf[3] & 3) << 11) | (_buf[4] << 3) | ((_buf[5] >> 5) & 0x07);
      final blocks = _buf[6] & 0x03;
      if (frameLen < headerLen || frameLen > 8191) {
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length < frameLen) return; // 等下一段
      final payload = Uint8List.fromList(_buf.sublist(headerLen, frameLen));
      _buf.removeRange(0, frameLen);
      if (payload.isEmpty) continue;
      if (sf > 12) {
        _invalid = true; // 采样率索引非法（保留/加密流）⇒ 放弃音轨
        _buf.clear();
        return;
      }
      sampleRate ??= _rates[sf];
      channels ??= ch == 0 ? 2 : ch;
      freqIndex ??= sf;
      objectType ??= profile + 1;
      final duration = 1024 * (blocks + 1);
      if (collect) {
        sizes.add(payload.length);
        durations.add(duration);
      }
      onFrame(payload, duration);
    }
  }
}

// ===========================================================================
// MP4 写盘
// ===========================================================================

class _VideoTiming {
  final List<int> dts; // 归一化（首样本 = 0）
  final List<int> durations; // 每样本时长（90kHz）
  final List<int> ctts; // PTS − DTS
  final List<int> keys; // stss（1-based）
  final int duration; // 总时长（90kHz）
  final int totalBytes;

  const _VideoTiming({
    required this.dts,
    required this.durations,
    required this.ctts,
    required this.keys,
    required this.duration,
    required this.totalBytes,
  });
}

_VideoTiming _videoTiming(List<_VideoSample> samples) {
  final n = samples.length;
  final base = samples.first.dts;
  final dts = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final v = samples[i].dts - base;
    dts[i] = v < 0 ? 0 : v;
  }
  // DTS 必须单调（B 帧流的 PES 顺序就是解码顺序；个别怪流给乱序值就夹一下）
  for (var i = 1; i < n; i++) {
    if (dts[i] <= dts[i - 1]) dts[i] = dts[i - 1] + 1;
  }
  final durations = List<int>.filled(n, 1);
  for (var i = 0; i < n; i++) {
    if (i + 1 < n) {
      durations[i] = dts[i + 1] - dts[i];
    } else if (n > 1) {
      durations[i] = dts[n - 1] - dts[n - 2];
    } else {
      durations[i] = 3000;
    }
    if (durations[i] <= 0) durations[i] = 1;
  }
  final ctts = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final v = samples[i].pts - samples[i].dts;
    ctts[i] = v > 0 ? v : 0;
  }
  final keys = <int>[];
  for (var i = 0; i < n; i++) {
    if (samples[i].key) keys.add(i + 1);
  }
  if (keys.isEmpty) keys.add(1); // 一个 IDR 都没有：别让播放器找不到入口
  var totalBytes = 0;
  for (final s in samples) {
    totalBytes += s.size;
  }
  return _VideoTiming(
    dts: dts,
    durations: durations,
    ctts: ctts,
    keys: keys,
    duration: dts[n - 1] + durations[n - 1],
    totalBytes: totalBytes,
  );
}

Uint8List _buildMoov(
  _Scan scan,
  _VideoTiming? video,
  _Chunks chunks,
) {
  final audio = scan.audio;
  final videoMs =
      video == null ? 0 : (video.duration * 1000 / 90000).round();
  var audioDuration = 0;
  if (audio != null) {
    for (final d in audio.durations) {
      audioDuration += d;
    }
  }
  final audioMs = audio == null
      ? 0
      : (audioDuration * 1000 / audio.sampleRate).round();
  final movieMs = math.max(videoMs, audioMs);

  final body = BytesBuilder(copy: false);
  body.add(_buildMvhd(movieMs));
  if (scan.video != null && video != null) {
    body.add(_buildVideoTrak(scan.video!, video, chunks.video, movieMs));
  }
  if (audio != null) {
    body.add(_buildAudioTrak(audio, chunks.audio, movieMs));
  }
  return _box('moov', body.takeBytes());
}

Uint8List _buildMvhd(int movieMs) {
  final p = BytesBuilder(copy: false);
  p.add(_u32(0)); // creation
  p.add(_u32(0)); // modification
  p.add(_u32(1000)); // timescale
  p.add(_u32(movieMs));
  p.add(_u32(0x00010000)); // rate 1.0
  p.add(_u16(0x0100)); // volume 1.0
  p.add(_u16(0));
  p.add(_u32(0));
  p.add(_u32(0));
  p.add(_matrix());
  for (var i = 0; i < 6; i++) {
    p.add(_u32(0));
  }
  p.add(_u32(3)); // next_track_ID
  return _fullBox('mvhd', 0, 0, p.takeBytes());
}

Uint8List _buildVideoTrak(
  _VideoInfo info,
  _VideoTiming t,
  List<_Chunk> chunks,
  int movieMs,
) {
  final stsd = _buildVideoStsd(info);
  final stts = _buildStts(t.durations);
  final ctts = _buildCtts(t.ctts);
  final stss = _buildStss(t.keys);
  final stsc = _buildStsc(chunks);
  final stsz = _buildStsz(_videoSizes(info.samples));
  final stco = _buildStco(chunks);
  return _buildTrak(
    trackId: 1,
    timescale: 90000,
    duration: t.duration,
    movieDurationMs: movieMs,
    handlerType: 'vide',
    handlerName: 'VideoHandler',
    mediaHeader: _buildVmhd(),
    stsd: stsd,
    stts: stts,
    ctts: ctts,
    stss: stss,
    stsc: stsc,
    stsz: stsz,
    stco: stco,
    width: info.width,
    height: info.height,
    volume: 0,
  );
}

Uint8List _buildAudioTrak(
  _AudioInfo info,
  List<_Chunk> chunks,
  int movieMs,
) {
  var duration = 0;
  for (final d in info.durations) {
    duration += d;
  }
  final stsd = _buildAudioStsd(info);
  final stts = _buildStts(info.durations);
  final stsc = _buildStsc(chunks);
  final stsz = _buildStsz(info.sizes);
  final stco = _buildStco(chunks);
  return _buildTrak(
    trackId: 2,
    timescale: info.sampleRate,
    duration: duration,
    movieDurationMs: movieMs,
    handlerType: 'soun',
    handlerName: 'SoundHandler',
    mediaHeader: _buildSmhd(),
    stsd: stsd,
    stts: stts,
    stsc: stsc,
    stsz: stsz,
    stco: stco,
    width: 0,
    height: 0,
    volume: 0x0100,
  );
}

List<int> _videoSizes(List<_VideoSample> s) =>
    <int>[for (final x in s) x.size];

Uint8List _buildTrak({
  required int trackId,
  required int timescale,
  required int duration,
  required int movieDurationMs,
  required String handlerType,
  required String handlerName,
  required Uint8List mediaHeader,
  required Uint8List stsd,
  required Uint8List stts,
  Uint8List? ctts,
  Uint8List? stss,
  required Uint8List stsc,
  required Uint8List stsz,
  required Uint8List stco,
  required int width,
  required int height,
  required int volume,
}) {
  final tkhd = BytesBuilder(copy: false);
  tkhd.add(_u32(0));
  tkhd.add(_u32(0));
  tkhd.add(_u32(trackId));
  tkhd.add(_u32(0)); // reserved
  tkhd.add(_u32(movieDurationMs));
  tkhd.add(_u32(0));
  tkhd.add(_u32(0));
  tkhd.add(_u16(0)); // layer
  tkhd.add(_u16(0)); // alternate_group
  tkhd.add(_u16(volume));
  tkhd.add(_u16(0));
  tkhd.add(_matrix());
  tkhd.add(_u32(width << 16));
  tkhd.add(_u32(height << 16));

  final mdhd = BytesBuilder(copy: false);
  mdhd.add(_u32(0));
  mdhd.add(_u32(0));
  mdhd.add(_u32(timescale));
  mdhd.add(_u32(duration));
  mdhd.add(_u16(0x55C4)); // language 'und'
  mdhd.add(_u16(0));

  final hdlr = BytesBuilder(copy: false);
  hdlr.add(_u32(0)); // pre_defined
  hdlr.add(_ascii(handlerType));
  hdlr.add(_u32(0));
  hdlr.add(_u32(0));
  hdlr.add(_u32(0));
  hdlr.add(_ascii(handlerName));
  hdlr.addByte(0);

  final dref = _fullBox(
    'dref',
    0,
    0,
    <int>[
      ..._u32(1),
      ..._fullBox('url ', 0, 1, const <int>[]),
    ],
  );
  final dinf = _box('dinf', dref);

  final stbl = _box('stbl', <int>[
    ...stsd,
    ...stts,
    if (ctts != null) ...ctts,
    if (stss != null) ...stss,
    ...stsc,
    ...stsz,
    ...stco,
  ]);
  final minf = _box('minf', <int>[...mediaHeader, ...dinf, ...stbl]);
  final mdia = _box('mdia', <int>[
    ..._fullBox('mdhd', 0, 0, mdhd.takeBytes()),
    ..._fullBox('hdlr', 0, 0, hdlr.takeBytes()),
    ...minf,
  ]);
  return _box('trak', <int>[
    ..._fullBox('tkhd', 0, 3, tkhd.takeBytes()),
    ...mdia,
  ]);
}

Uint8List _buildVmhd() => _fullBox(
      'vmhd',
      0,
      1,
      <int>[..._u16(0), ..._u16(0), ..._u16(0), ..._u16(0)],
    );

Uint8List _buildSmhd() => _fullBox('smhd', 0, 0, <int>[..._u16(0), ..._u16(0)]);

Uint8List _buildVideoStsd(_VideoInfo info) {
  final p = BytesBuilder(copy: false);
  p.add(Uint8List(6)); // reserved
  p.add(_u16(1)); // data_reference_index
  p.add(_u16(0)); // pre_defined
  p.add(_u16(0)); // reserved
  p.add(_u32(0));
  p.add(_u32(0));
  p.add(_u32(0));
  p.add(_u16(info.width));
  p.add(_u16(info.height));
  p.add(_u32(0x00480000)); // 72 dpi
  p.add(_u32(0x00480000));
  p.add(_u32(0)); // reserved
  p.add(_u16(1)); // frame_count
  p.add(Uint8List(32)); // compressorname
  p.add(_u16(0x0018)); // depth
  p.add(_u16(0xFFFF)); // pre_defined
  p.add(_buildAvcC(info.sps, info.pps));
  final entry = _box('avc1', p.takeBytes());
  return _fullBox('stsd', 0, 0, <int>[..._u32(1), ...entry]);
}

Uint8List _buildAvcC(Uint8List sps, Uint8List pps) {
  final p = BytesBuilder(copy: false);
  p.addByte(1); // configurationVersion
  p.addByte(sps.length > 1 ? sps[1] : 0); // AVCProfileIndication
  p.addByte(sps.length > 2 ? sps[2] : 0); // profile_compatibility
  p.addByte(sps.length > 3 ? sps[3] : 0); // AVCLevelIndication
  p.addByte(0xFF); // lengthSizeMinusOne = 3
  p.addByte(0xE1); // numOfSequenceParameterSets = 1
  p.add(_u16(sps.length));
  p.add(sps);
  p.addByte(0x01); // numOfPictureParameterSets
  p.add(_u16(pps.length));
  p.add(pps);
  return _box('avcC', p.takeBytes());
}

Uint8List _buildAudioStsd(_AudioInfo info) {
  final p = BytesBuilder(copy: false);
  p.add(Uint8List(6)); // reserved
  p.add(_u16(1)); // data_reference_index
  p.add(_u32(0)); // reserved
  p.add(_u32(0));
  p.add(_u16(info.channels));
  p.add(_u16(16)); // samplesize
  p.add(_u16(0)); // pre_defined
  p.add(_u16(0)); // reserved
  p.add(_u32((info.sampleRate & 0xFFFF) << 16));
  p.add(_buildEsds(info));
  final entry = _box('mp4a', p.takeBytes());
  return _fullBox('stsd', 0, 0, <int>[..._u32(1), ...entry]);
}

Uint8List _buildEsds(_AudioInfo info) {
  final asc = _buildAsc(info);
  final dsi = _descriptor(0x05, asc);
  var totalSamples = 0;
  for (final d in info.durations) {
    totalSamples += d;
  }
  var totalBytes = 0;
  for (final s in info.sizes) {
    totalBytes += s;
  }
  final seconds = totalSamples <= 0 ? 1.0 : totalSamples / info.sampleRate;
  final avgBitrate =
      (totalBytes * 8 / seconds).round().clamp(0, 0x7FFFFFFF).toInt();
  final dcd = BytesBuilder(copy: false);
  dcd.addByte(0x40); // objectTypeIndication: MPEG-4 Audio
  dcd.addByte(0x15); // streamType=audio(5)<<2 | upStream=0 | reserved=1
  dcd.add(_u24(0)); // bufferSizeDB
  dcd.add(_u32(avgBitrate)); // maxBitrate
  dcd.add(_u32(avgBitrate)); // avgBitrate
  dcd.add(dsi);
  final es = BytesBuilder(copy: false);
  es.add(_u16(1)); // ES_ID
  es.addByte(0); // flags
  es.add(_descriptor(0x04, dcd.takeBytes()));
  es.add(_descriptor(0x06, Uint8List.fromList(<int>[0x02])));
  return _fullBox('esds', 0, 0, _descriptor(0x03, es.takeBytes()));
}

/// AudioSpecificConfig：5 bit AOT + 4 bit 频率索引 + 4 bit 声道 + 3 bit 0
Uint8List _buildAsc(_AudioInfo info) {
  final bits = ((info.objectType & 0x1F) << 11) |
      ((info.freqIndex & 0x0F) << 7) |
      ((info.channels & 0x0F) << 3);
  return Uint8List.fromList(<int>[(bits >> 8) & 0xFF, bits & 0xFF]);
}

Uint8List _descriptor(int tag, Uint8List payload) {
  final b = BytesBuilder(copy: false);
  b.addByte(tag);
  var size = payload.length;
  final bytes = <int>[size & 0x7F];
  size >>= 7;
  while (size > 0) {
    bytes.insert(0, (size & 0x7F) | 0x80);
    size >>= 7;
  }
  b.add(bytes);
  b.add(payload);
  return b.takeBytes();
}

Uint8List _buildStts(List<int> durations) {
  final runs = _runLength(durations);
  final p = BytesBuilder(copy: false);
  p.add(_u32(runs.length));
  for (final r in runs) {
    p.add(_u32(r[0]));
    p.add(_u32(r[1]));
  }
  return _fullBox('stts', 0, 0, p.takeBytes());
}

Uint8List _buildCtts(List<int> offsets) {
  final runs = _runLength(offsets);
  final p = BytesBuilder(copy: false);
  p.add(_u32(runs.length));
  for (final r in runs) {
    p.add(_u32(r[0]));
    p.add(_u32(r[1]));
  }
  return _fullBox('ctts', 0, 0, p.takeBytes());
}

Uint8List _buildStss(List<int> keys) {
  final p = BytesBuilder(copy: false);
  p.add(_u32(keys.length));
  for (final k in keys) {
    p.add(_u32(k));
  }
  return _fullBox('stss', 0, 0, p.takeBytes());
}

Uint8List _buildStsc(List<_Chunk> chunks) {
  final entries = <List<int>>[];
  var i = 0;
  while (i < chunks.length) {
    final spc = chunks[i].samples;
    var j = i;
    while (j + 1 < chunks.length && chunks[j + 1].samples == spc) {
      j++;
    }
    entries.add(<int>[i + 1, spc, 1]);
    i = j + 1;
  }
  final p = BytesBuilder(copy: false);
  p.add(_u32(entries.length));
  for (final e in entries) {
    p.add(_u32(e[0]));
    p.add(_u32(e[1]));
    p.add(_u32(e[2]));
  }
  return _fullBox('stsc', 0, 0, p.takeBytes());
}

Uint8List _buildStsz(List<int> sizes) {
  final p = BytesBuilder(copy: false);
  p.add(_u32(0)); // sample_size = 0（每样本不同）
  p.add(_u32(sizes.length));
  for (final s in sizes) {
    p.add(_u32(s));
  }
  return _fullBox('stsz', 0, 0, p.takeBytes());
}

Uint8List _buildStco(List<_Chunk> chunks) {
  final p = BytesBuilder(copy: false);
  p.add(_u32(chunks.length));
  for (final c in chunks) {
    p.add(_u32(c.offset));
  }
  return _fullBox('stco', 0, 0, p.takeBytes());
}

List<List<int>> _runLength(List<int> values) {
  final out = <List<int>>[];
  var i = 0;
  while (i < values.length) {
    final v = values[i];
    var j = i;
    while (j + 1 < values.length && values[j + 1] == v) {
      j++;
    }
    out.add(<int>[j - i + 1, v]);
    i = j + 1;
  }
  return out;
}

// ===========================================================================
// 小工具
// ===========================================================================

Uint8List _buildFtyp() {
  final p = BytesBuilder(copy: false);
  p.add(_ascii('isom'));
  p.add(_u32(0x200));
  for (final brand in const <String>['isom', 'iso2', 'avc1', 'mp41']) {
    p.add(_ascii(brand));
  }
  return _box('ftyp', p.takeBytes());
}

Uint8List _buildMdatHeader(int dataBytes) {
  if (dataBytes + 8 <= 0xFFFFFFFF) {
    return _boxHeader('mdat', dataBytes + 8);
  }
  // 大文件：64 位 largesize（size=1 + type + uint64）
  final p = BytesBuilder(copy: false);
  p.add(_u32(1));
  p.add(_ascii('mdat'));
  p.add(_u64(dataBytes + 16));
  return p.takeBytes();
}

Uint8List _box(String type, List<int> payload) {
  final p = BytesBuilder(copy: false);
  p.add(_u32(8 + payload.length));
  p.add(_ascii(type));
  p.add(payload);
  return p.takeBytes();
}

Uint8List _boxHeader(String type, int size) {
  final p = BytesBuilder(copy: false);
  p.add(_u32(size));
  p.add(_ascii(type));
  return p.takeBytes();
}

Uint8List _fullBox(String type, int version, int flags, List<int> payload) {
  return _box(type, <int>[
    version,
    (flags >> 16) & 0xFF,
    (flags >> 8) & 0xFF,
    flags & 0xFF,
    ...payload,
  ]);
}

Uint8List _matrix() => Uint8List.fromList(<int>[
      ..._u32(0x00010000),
      ..._u32(0),
      ..._u32(0),
      ..._u32(0),
      ..._u32(0x00010000),
      ..._u32(0),
      ..._u32(0),
      ..._u32(0),
      ..._u32(0x40000000),
    ]);

Uint8List _u16(int v) =>
    Uint8List.fromList(<int>[(v >> 8) & 0xFF, v & 0xFF]);

Uint8List _u24(int v) =>
    Uint8List.fromList(<int>[(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);

Uint8List _u32(int v) => Uint8List.fromList(<int>[
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ]);

Uint8List _u64(int v) => Uint8List.fromList(<int>[
      (v >> 56) & 0xFF,
      (v >> 48) & 0xFF,
      (v >> 40) & 0xFF,
      (v >> 32) & 0xFF,
      (v >> 24) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 8) & 0xFF,
      v & 0xFF,
    ]);

Uint8List _ascii(String s) =>
    Uint8List.fromList(<int>[for (final c in s.codeUnits) c & 0xFF]);
