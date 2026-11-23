mdx-voc-ft.tflite
来源：UVR-MDX-NET-Voc_FT（UVR / MDX-Net 公开模型，经 PixlAudio 的 LiteRT float32 导出）
大小：66,848,828 bytes
SHA256：5ef47e3b3bafa14357532c0a3f6c5f18444d94b6efe3fd62b3d13f80051f1e58

输入/输出：float32 [1, 4, 3072, 256]，planes = L-real, L-imag, R-real, R-imag，
44.1 kHz / 6144 点 FFT / hop 1024 / 256 帧。模型只预测人声频谱；
伴奏由立体声联动的互补掩码从原频谱重建。
仅用于个人非商业用途的本地伴唱/分离；模型权利归 UVR / MDX-Net 上游作者所有。
