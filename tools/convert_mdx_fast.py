import os, time, tarfile, urllib.request
import numpy as np
import onnx, torch
from onnx2torch import convert
import coremltools as ct

NAME = "MdxNetFast9703"
ONNX_NAME = "UVR_MDXNET_1_9703.onnx"
URL = "https://github.com/TRvlvr/model_repo/releases/download/all_public_uvr_models/" + ONNX_NAME
DIM_F = 2048
os.makedirs("out", exist_ok=True)
path = "out/" + ONNX_NAME
if not os.path.exists(path):
    urllib.request.urlretrieve(URL, path)
print("onnx", os.path.getsize(path))
tm = convert(onnx.load(path)).eval()
x = torch.randn(1, 4, DIM_F, 256)
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
t0 = time.time()
mm = ct.convert(
    traced, source="pytorch",
    inputs=[ct.TensorType(name="spectrum", shape=(1, 4, DIM_F, 256), dtype=np.float32)],
    outputs=[ct.TensorType(name="vocals", dtype=np.float32)],
    convert_to="mlprogram", compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.iOS15,
    skip_model_load=True,
)
package = f"out/{NAME}_iOS15.mlpackage"
mm.save(package)
spec = ct.utils.load_spec(package + "/Data/com.apple.CoreML/model.mlmodel")
print("ok", spec.specificationVersion, spec.mlProgram.functions["main"].opset, round(time.time()-t0,1))
with tarfile.open(f"out/{NAME}_iOS15.mlpackage.tar", "w") as tar:
    tar.add(package, arcname=os.path.basename(package))
