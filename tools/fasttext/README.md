Training fastText intent classifier for ckp_temp app

Overview
- The script `train_fasttext.py` extracts labeled examples from the app SQLite DB or a labeled CSV.
- It trains a supervised fastText classifier and outputs `fasttext_model.bin` into the `--out` directory.

Quickstart
1. Create a virtualenv and install dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r tools/fasttext/requirements.txt
```

2. Extract and train (example using db):

```bash
python tools/fasttext/train_fasttext.py --db /path/to/catatan_keuangan.db --out ./models
```

3. The model will be saved to `./models/fasttext_model.bin` which you can load in Flutter via a tiny native binding or by using a small server wrapper. The model file is typically small (<10 MB) depending on labels/vocab.

Integration notes
- Include `fasttext_model.bin` as a downloadable asset (not bundled in APK) and load it at runtime.
- On Android/iOS you can use native libraries for fastText or call a lightweight server. Alternatively export to TensorFlow/NAN for tflite conversion (not covered here).

""
