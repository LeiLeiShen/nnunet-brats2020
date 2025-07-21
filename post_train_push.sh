#!/bin/bash

# === 设置变量 ===
REPO_DIR="/workspace/nnunet-brats2020"
RESULTS_REPO_DIR="/workspace/nnunet-results"
OUTPUT_DIR="/workspace/output"
BRANCH="main"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_SUBDIR="results_$TIMESTAMP"
RCLONE_CONF_PATH="$REPO_DIR/rclone.conf"

# === 克隆结果仓库（如果还未拉取） ===
if [ ! -d "$RESULTS_REPO_DIR/.git" ]; then
  git clone https://github.com/LeiLeiShen/nnunet-results.git "$RESULTS_REPO_DIR"
fi

# === 设置 Git 身份（可选） ===
git config --global user.name "LeiLeiShen"
git config --global user.email "lshen21@students.desu.edu"

# === 生成 loss 和 dice 曲线图 ===
echo "📈 Generating loss and dice curves..."

python <<EOF
import json
import matplotlib.pyplot as plt
import os

output_dir = "$OUTPUT_DIR"
result_dir = os.path.join("$RESULTS_REPO_DIR", "$RESULTS_SUBDIR")
os.makedirs(result_dir, exist_ok=True)

log_file = os.path.join(output_dir, "logs.json")
if os.path.exists(log_file):
    with open(log_file) as f:
        logs = json.load(f)

    epochs = list(range(len(logs["dice"])))
    dice_total = logs["dice"]
    d1 = logs["dice_per_class"]["1"]
    d2 = logs["dice_per_class"]["2"]
    d3 = logs["dice_per_class"]["3"]
    train_loss = logs["train_loss"]
    val_loss = logs["val_loss"]

    plt.figure(figsize=(12, 6))
    plt.subplot(1, 2, 1)
    plt.plot(epochs, train_loss, label='Train Loss')
    plt.plot(epochs, val_loss, label='Val Loss')
    plt.xlabel("Epoch")
    plt.ylabel("Loss")
    plt.title("Loss Curve")
    plt.legend()

    plt.subplot(1, 2, 2)
    plt.plot(epochs, dice_total, label='Dice')
    plt.plot(epochs, d1, label='Dice D1')
    plt.plot(epochs, d2, label='Dice D2')
    plt.plot(epochs, d3, label='Dice D3')
    plt.xlabel("Epoch")
    plt.ylabel("Dice Score")
    plt.title("Dice Score Curve")
    plt.legend()

    fig_path = os.path.join(result_dir, "training_curves.png")
    plt.tight_layout()
    plt.savefig(fig_path)
    print(f"✅ Saved training curves to {fig_path}")
else:
    print("⚠️ logs.json not found, skipping curve generation.")
EOF

# === 拷贝训练结果到结果仓库 ===
mkdir -p "$RESULTS_REPO_DIR/$RESULTS_SUBDIR"
cp -r "$OUTPUT_DIR/checkpoints" "$RESULTS_REPO_DIR/$RESULTS_SUBDIR/"
cp "$OUTPUT_DIR/logs.json" "$RESULTS_REPO_DIR/$RESULTS_SUBDIR/"
cp "$OUTPUT_DIR/params.json" "$RESULTS_REPO_DIR/$RESULTS_SUBDIR/"

# === Git 推送到 nnunet-results 仓库 ===
cd "$RESULTS_REPO_DIR"
git add "$RESULTS_SUBDIR/logs.json" "$RESULTS_SUBDIR/params.json" "$RESULTS_SUBDIR/training_curves.png"
git commit -m "Auto commit: add training results $RESULTS_SUBDIR"
git push origin "$BRANCH"

# === 上传训练结果到 Google Drive via rclone.conf（来自仓库） ===
echo "📤 Uploading results to Google Drive..."

rclone copy "$RESULTS_REPO_DIR/$RESULTS_SUBDIR" gdrive:nnunet_results/"$RESULTS_SUBDIR" --config="$RCLONE_CONF_PATH" --progress

# === 自动关闭 RunPod 实例 ===
if [[ -n "$RUNPOD_API_KEY" && -n "$RUNPOD_POD_ID" ]]; then
  echo "Shutting down RunPod instance $RUNPOD_POD_ID..."
  curl -X POST https://api.runpod.io/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $RUNPOD_API_KEY" \
    -d '{
      "query": "mutation ControlPod($podId: String!) { controlPod(input: { podId: $podId, action: STOP }) { podId status } }",
      "variables": { "podId": "'"$RUNPOD_POD_ID"'" }
    }'
else
  echo "⚠️ RUNPOD_API_KEY 或 RUNPOD_POD_ID 未设置，无法关闭实例"
fi
