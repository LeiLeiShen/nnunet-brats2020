#!/bin/bash
set -e

# === 基本变量 ===
REPO_DIR="/workspace/nnunet-brats2020"
RESULTS_REPO_DIR="/workspace/nnunet-results"
OUTPUT_DIR="/workspace/output"
BRANCH="main"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_SUBDIR="results_$TIMESTAMP"
RCLONE_CONF_PATH="$REPO_DIR/rclone.conf"

GIT_USERNAME="LeiLeiShen"
GIT_EMAIL="lshen21@students.desu.edu"
# ☆☆☆ 把自己的 PAT 填入环境变量；脚本里只留占位以防忘记
GIT_TOKEN="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"

# === 克隆结果仓库（若尚未存在） ===
if [ ! -d "$RESULTS_REPO_DIR/.git" ]; then
  git clone https://github.com/$GIT_USERNAME/nnunet-results.git "$RESULTS_REPO_DIR"
fi

# === Git 配置 ===
git config --global user.name "$GIT_USERNAME"
git config --global user.email "$GIT_EMAIL"

# === 生成训练曲线图（如 logs.json 有内容） ===
echo "📈 Generating loss and dice curves..."
python <<'PY'
import json, os, matplotlib.pyplot as plt
output_dir = "/workspace/output"
result_dir = "/workspace/nnunet-results/results_${TIMESTAMP}"
os.makedirs(result_dir, exist_ok=True)
log_file = os.path.join(output_dir, "logs.json")
if os.path.exists(log_file) and os.path.getsize(log_file) > 10:
    try:
        logs = json.load(open(log_file))
        if logs.get("dice"):
            epochs = list(range(len(logs["dice"])))
            plt.plot(epochs, logs["dice"], label="Dice")
            plt.legend(); plt.xlabel("Epoch"); plt.ylabel("Dice"); plt.title("Dice Curve")
            plt.tight_layout(); plt.savefig(os.path.join(result_dir, "training_curves.png"))
            print("✅ Saved curve")
        else:
            print("⚠️ dice key empty; skip curve")
    except Exception as e:
        print(f"⚠️ Parse error {e}; skip curve")
else:
    print("⚠️ logs.json missing or empty; skip curve")
PY

# === 拷贝原始结果文件 ===
mkdir -p "$RESULTS_REPO_DIR/$RESULTS_SUBDIR"
cp -r "$OUTPUT_DIR/checkpoints" "$RESULTS_REPO_DIR/$RESULTS_SUBDIR/" 2>/dev/null || true
cp "$OUTPUT_DIR"/{logs.json,params.json} "$RESULTS_REPO_DIR/$RESULTS_SUBDIR/" 2>/dev/null || true

# === Git 提交 & 推送（无交互） ===
cd "$RESULTS_REPO_DIR"
git checkout "$BRANCH" || git checkout -b "$BRANCH"
git add "$RESULTS_SUBDIR"/* || true
git commit -m "Auto commit: add training results $RESULTS_SUBDIR" || echo "⚠️ Nothing to commit."

# ★★ 关键：token 作为“用户名”，无密码 ★★
git remote set-url origin https://$GIT_TOKEN@github.com/$GIT_USERNAME/nnunet-results.git
git push origin "$BRANCH" || echo "⚠️ Git push failed."

# === 上传 Google Drive ===
echo "📤 Uploading to Google Drive..."
if [ -f "$RCLONE_CONF_PATH" ]; then
  rclone copy "$RESULTS_REPO_DIR/$RESULTS_SUBDIR" gdrive:nnunet_results/"$RESULTS_SUBDIR" --config="$RCLONE_CONF_PATH" --progress
else
  echo "⚠️ rclone.conf not found; skip GDrive upload."
fi

