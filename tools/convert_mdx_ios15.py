import os, sys, time, json, urllib.request, tarfile
import numpy as np
import onnx, torch
from onnx2torch import convert
import coremltools as ct

URL = "https://github.com/TRvlvr/model_repo/releases/download/all_public_uvr_models/UVR-MDX-NET-Voc_FT.onnx"
os.makedirs("out", exist_ok=True)
path = "out/UVR-MDX-NET-Voc_FT.onnx"
if not os.path.exists(path):
    urllib.request.urlretrieve(URL, path)
print("onnx", os.path.getsize(path))
graph = onnx.load(path)
tm = convert(graph).eval()
x = torch.randn(1, 4, 3072, 256)
with torch.no_grad():
    y = tm(x)
    if isinstance(y, (list, tuple)): y = y[0]
print("torch", y.shape, float(y.abs().max()))

class W(torch.nn.Module):
    def __init__(self, inner): super().__init__(); self.inner = inner
    def forward(self, x):
        y = self.inner(x)
        return y[0] if isinstance(y, (list, tuple)) else y

traced = torch.jit.trace(W(tm).eval(), x, check_trace=False)
for target, name in [(ct.target.iOS15, "iOS15"), (ct.target.iOS16, "iOS16"), (ct.target.iOS17, "iOS17")]:
    try:
        t0 = time.time()
        mm = ct.convert(
            traced, source="pytorch",
            inputs=[ct.TensorType(name="spectrum", shape=(1, 4, 3072, 256), dtype=np.float32)],
            outputs=[ct.TensorType(name="vocals", dtype=np.float32)],
            convert_to="mlprogram", compute_precision=ct.precision.FLOAT16,
            minimum_deployment_target=target,
            skip_model_load=True,
        )
        package = f"out/MdxNetVocFT_{name}.mlpackage"
        mm.save(package)
        spec = ct.utils.load_spec(package + "/Data/com.apple.CoreML/model.mlmodel")
        print(name, "ok", spec.specificationVersion, spec.mlProgram.functions["main"].opset,
              "seconds", round(time.time()-t0, 1))
        with tarfile.open(f"out/mdx_net_voc_ft_{name}.mlpackage.tar", "w") as tar:
            tar.add(package, arcname=os.path.basename(package))
    except Exception as e:
        print(name, "FAILED", type(e).__name__, e)
        import traceback; traceback.print_exc()
