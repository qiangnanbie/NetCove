# 播放验收矩阵（自动生成）

共 **149** 条用例。用 `python3 tools/tuning_matrix.py generate --full` 可生成全量笛卡尔积。

填完 `matrix.csv` 的 `hardware_decode / startup_ms / dropped_frames / power_mw / verdict` 后，
运行 `python3 tools/tuning_matrix.py apply spec/tuning/matrix.csv` 生成参数文件。

**判定线（建议）**：起播 ≤ 1500 ms、掉帧率 ≤ 1%、硬解成功、功耗 ≤ 3500 mW。


## avi（24 条）

| id | 视频 | 帧率 | 分辨率 | 音频 | 字幕 | 交互 | 预期引擎 | 结果 |
|---|---|---|---|---|---|---|---|---|
| C0073 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0074 | h264_8bit_sdr | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0075 | h264_8bit_sdr | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0076 | h264_8bit_sdr | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0077 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0078 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0079 | hevc_10bit_hdr10 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0080 | hevc_10bit_hdr10 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0081 | dv_p5 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0082 | dv_p5 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0083 | dv_p5 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0084 | dv_p5 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0085 | dv_p8 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0086 | dv_p8 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0087 | dv_p8 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0088 | dv_p8 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0089 | hlg | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0090 | hlg | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0091 | hlg | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0092 | hlg | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0093 | av1_10bit | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0094 | av1_10bit | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0095 | av1_10bit | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0096 | av1_10bit | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |

## mkv（40 条）

| id | 视频 | 帧率 | 分辨率 | 音频 | 字幕 | 交互 | 预期引擎 | 结果 |
|---|---|---|---|---|---|---|---|---|
| C0025 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0026 | h264_8bit_sdr | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0027 | h264_8bit_sdr | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0028 | h264_8bit_sdr | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0029 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0030 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0031 | hevc_10bit_hdr10 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0032 | hevc_10bit_hdr10 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0033 | dv_p5 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0034 | dv_p5 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0035 | dv_p5 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0036 | dv_p5 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0037 | dv_p8 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0038 | dv_p8 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0039 | dv_p8 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0040 | dv_p8 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0041 | hlg | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0042 | hlg | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0043 | hlg | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0044 | hlg | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0045 | av1_10bit | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0046 | av1_10bit | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0047 | av1_10bit | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0048 | av1_10bit | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0121 | hevc_10bit_hdr10 | 23.976 | 1280×720 | aac | srt | startup | ffmpeg | ☐ |
| C0122 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0123 | hevc_10bit_hdr10 | 23.976 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0124 | hevc_10bit_hdr10 | 30 | 1280×720 | aac | srt | startup | ffmpeg | ☐ |
| C0125 | hevc_10bit_hdr10 | 30 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0126 | hevc_10bit_hdr10 | 30 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0127 | hevc_10bit_hdr10 | 60 | 1280×720 | aac | srt | startup | ffmpeg | ☐ |
| C0128 | hevc_10bit_hdr10 | 60 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0129 | hevc_10bit_hdr10 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0130 | hevc_10bit_hdr10 | 120 | 1280×720 | aac | srt | startup | ffmpeg | ☐ |
| C0131 | hevc_10bit_hdr10 | 120 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0132 | hevc_10bit_hdr10 | 120 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0140 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | none | startup | ffmpeg | ☐ |
| C0141 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0142 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | ass | startup | ffmpeg | ☐ |
| C0143 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | pgs | startup | ffmpeg | ☐ |

## mp4（37 条）

| id | 视频 | 帧率 | 分辨率 | 音频 | 字幕 | 交互 | 预期引擎 | 结果 |
|---|---|---|---|---|---|---|---|---|
| C0001 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | startup | avplayer | ☐ |
| C0002 | h264_8bit_sdr | 23.976 | 1920×1080 | eac3 | ass | seek | avplayer | ☐ |
| C0003 | h264_8bit_sdr | 60 | 3840×2160 | aac | srt | startup | avplayer | ☐ |
| C0004 | h264_8bit_sdr | 60 | 3840×2160 | eac3 | ass | seek | avplayer | ☐ |
| C0005 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | aac | srt | startup | avplayer | ☐ |
| C0006 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | eac3 | ass | seek | avplayer | ☐ |
| C0007 | hevc_10bit_hdr10 | 60 | 3840×2160 | aac | srt | startup | avplayer | ☐ |
| C0008 | hevc_10bit_hdr10 | 60 | 3840×2160 | eac3 | ass | seek | avplayer | ☐ |
| C0009 | dv_p5 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0010 | dv_p5 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0011 | dv_p5 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0012 | dv_p5 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0013 | dv_p8 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0014 | dv_p8 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0015 | dv_p8 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0016 | dv_p8 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0017 | hlg | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0018 | hlg | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0019 | hlg | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0020 | hlg | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0021 | av1_10bit | 23.976 | 1920×1080 | aac | srt | startup | avplayer | ☐ |
| C0022 | av1_10bit | 23.976 | 1920×1080 | eac3 | ass | seek | avplayer | ☐ |
| C0023 | av1_10bit | 60 | 3840×2160 | aac | srt | startup | avplayer | ☐ |
| C0024 | av1_10bit | 60 | 3840×2160 | eac3 | ass | seek | avplayer | ☐ |
| C0133 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | none | audio-switch | avplayer | ☐ |
| C0134 | h264_8bit_sdr | 23.976 | 1920×1080 | ac3 | none | audio-switch | avplayer | ☐ |
| C0135 | h264_8bit_sdr | 23.976 | 1920×1080 | eac3 | none | audio-switch | avplayer | ☐ |
| C0136 | h264_8bit_sdr | 23.976 | 1920×1080 | dts | none | audio-switch | avplayer | ☐ |
| C0137 | h264_8bit_sdr | 23.976 | 1920×1080 | truehd | none | audio-switch | avplayer | ☐ |
| C0138 | h264_8bit_sdr | 23.976 | 1920×1080 | flac | none | audio-switch | avplayer | ☐ |
| C0139 | h264_8bit_sdr | 23.976 | 1920×1080 | opus | none | audio-switch | avplayer | ☐ |
| C0144 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | startup | avplayer | ☐ |
| C0145 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | seek | avplayer | ☐ |
| C0146 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | rate2x | avplayer | ☐ |
| C0147 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | audio-switch | avplayer | ☐ |
| C0148 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | pip | avplayer | ☐ |
| C0149 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | airplay | avplayer | ☐ |

## strm（24 条）

| id | 视频 | 帧率 | 分辨率 | 音频 | 字幕 | 交互 | 预期引擎 | 结果 |
|---|---|---|---|---|---|---|---|---|
| C0097 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0098 | h264_8bit_sdr | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0099 | h264_8bit_sdr | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0100 | h264_8bit_sdr | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0101 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0102 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0103 | hevc_10bit_hdr10 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0104 | hevc_10bit_hdr10 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0105 | dv_p5 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0106 | dv_p5 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0107 | dv_p5 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0108 | dv_p5 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0109 | dv_p8 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0110 | dv_p8 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0111 | dv_p8 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0112 | dv_p8 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0113 | hlg | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0114 | hlg | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0115 | hlg | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0116 | hlg | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0117 | av1_10bit | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0118 | av1_10bit | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0119 | av1_10bit | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0120 | av1_10bit | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |

## ts（24 条）

| id | 视频 | 帧率 | 分辨率 | 音频 | 字幕 | 交互 | 预期引擎 | 结果 |
|---|---|---|---|---|---|---|---|---|
| C0049 | h264_8bit_sdr | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0050 | h264_8bit_sdr | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0051 | h264_8bit_sdr | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0052 | h264_8bit_sdr | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0053 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0054 | hevc_10bit_hdr10 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0055 | hevc_10bit_hdr10 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0056 | hevc_10bit_hdr10 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0057 | dv_p5 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0058 | dv_p5 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0059 | dv_p5 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0060 | dv_p5 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0061 | dv_p8 | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0062 | dv_p8 | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0063 | dv_p8 | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0064 | dv_p8 | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0065 | hlg | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0066 | hlg | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0067 | hlg | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0068 | hlg | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
| C0069 | av1_10bit | 23.976 | 1920×1080 | aac | srt | startup | ffmpeg | ☐ |
| C0070 | av1_10bit | 23.976 | 1920×1080 | eac3 | ass | seek | ffmpeg | ☐ |
| C0071 | av1_10bit | 60 | 3840×2160 | aac | srt | startup | ffmpeg | ☐ |
| C0072 | av1_10bit | 60 | 3840×2160 | eac3 | ass | seek | ffmpeg | ☐ |
