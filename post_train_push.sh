#!/bin/bash 

set -e

# === 设置变量 ===
REPO_DIR="/workspace/nnunet-brats2020"
RESULTS_REPO_DIR="/workspace/nnunet-results"
OUTPUT_DIR="/workspace/output"
BRANCH="main"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_SUBDIR="results_$TIMESTAMP"
RCLONE_CONF_PATH="$REPO_DIR/rclone.conf"

# === 克隆结果仓库 ===
if [ ! -d "$RESULTS_REPO_DIR/.git" ]; then
  git clone https://github.com/LeiLeiShen/nnunet-results.git "$RESULTS_REPO_DIR"
fi

# === 设置 Git 身份 ===
git config --global user.name "LeiLeiShen"
git config --global user.email "lshen21@students.desu.edu"

# === 生成训练曲线图 ===
echo "📈 Generating loss and dice curves..."

python <<EOF
import json
import matplotlib.pyplot as plt
import os

output_dir = "$OUTPUT_DIR"
result_dir = os.path.join("$RESULTS_REPO_DIR", "$RESULTS_SUBDIR")
os.makedirs(result_dir, exist_ok=True)

log_file = os.path.join(output_dir, "logs.json")

def safe_get(logs, key, default_len):
    return logs.get(key, [None] * default_len)

if os.path.exists(log_file) and os.path.getsize(log_file) > 0:
    try:
        with open(log_file) as f:
            logs = json.load(f)

        if logs.get("dice") and len(logs["dice"]) > 0:
            epochs = list(range(len(logs["dice"])))
            dice_total = safe_get(logs, "dice", len(epochs))
            dice_per_class = logs.get("dice_per_class", {})
            d1 = safe_get(dice_per_class, "1", len(epochs))
            d2 = safe_get(dice_per_class, "2", len(epochs))
            d3 = safe_get(dice_per_class, "3", len(epochs))
            train_loss = safe_get(logs, "train_loss", len(epochs))
            val_loss = safe_get(logs, "val_loss", len(epochs))

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
            print("⚠️ logs.json exists but dice key is empty. Skipping.")
    except Exception as e:
        print(f"⚠️ Error while parsing logs.json: {e}. Skipping curve generation.")
else:
    print("⚠️ logs.json not found or empty. Skipping curve generation.")
EOF

# === 拷贝训练结果到结果仓库 ===
mkdir -p "$RESULTS_REPO_DIR/$RESULTS_SUBDIR"
cp -r "$OUTPUT_DIR/checkpoints" "$RESULTS_REPO_DIR/$RESULTS_SUBDIR/" 2>/dev/null || true
cp "$OUTPUT_DIR/logs.json" "$RESULTS_REPO_DIR/$RESULTS_SUBDIR/" 2>/dev/null || true
cp "$OUTPUT_DIR/params.json" "$RESULTS_REPO_DIR/$RESULTS_SUBDIR/" 2>/dev/null || true

# === Git 推送到 nnunet-results 仓库 ===
cd "$RESULTS_REPO_DIR"
git checkout main || git checkout -b main
git add "$RESULTS_SUBDIR"/*
git commit -m "Auto commit: add training results $RESULTS_SUBDIR" || echo "⚠️ Nothing to commit."
# 使用 GitHub Token 进行无交互推送
GIT_TOKEN=${GITHUB_TOKEN:-"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"}
git remote set-url origin https://$GIT_TOKEN@github.com/LeiLeiShen/nnunet-results.git
git push origin main || echo "⚠️ Git push failed."


# === 上传训练结果到 Google Drive via rclone ===
echo "📤 Uploading results to Google Drive..."

if [ -f "$RCLONE_CONF_PATH" ]; then
  rclone copy "$RESULTS_REPO_DIR/$RESULTS_SUBDIR" gdrive:nnunet_results/"$RESULTS_SUBDIR" --config="$RCLONE_CONF_PATH" --progress
else
  echo "⚠️ rclone.conf not found at $RCLONE_CONF_PATH. Skipping Google Drive upload."
fi

# === 自动关闭 RunPod 实例（非必需）===
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
  echo "ℹ️ 跳过自动关闭 RunPod。RUNPOD_API_KEY 或 POD_ID 未配置。"
fi
