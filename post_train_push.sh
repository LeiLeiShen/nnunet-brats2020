#!/bin/bash

# === 设置变量 ===
REPO_DIR="/workspace/nnunet-brats2020"
OUTPUT_DIR="/workspace/output"
BRANCH="main"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_SUBDIR="results_$TIMESTAMP"

# === 进入代码仓库目录 ===
cd "$REPO_DIR" || exit

# === 设置 Git 身份（可选） ===
git config --global user.name "LeiLeiShen"
git config --global user.email "lshen21@students.desu.edu"

# === 拷贝训练结果到本地 repo 文件夹 ===
mkdir -p "$REPO_DIR/$RESULTS_SUBDIR"
cp -r "$OUTPUT_DIR/checkpoints" "$REPO_DIR/$RESULTS_SUBDIR/"
cp "$OUTPUT_DIR/logs.json" "$REPO_DIR/$RESULTS_SUBDIR/"
cp "$OUTPUT_DIR/params.json" "$REPO_DIR/$RESULTS_SUBDIR/"

# === Git 推送（可选）: 仅日志和配置，不含大模型文件 ===
cd "$REPO_DIR"
git add "$RESULTS_SUBDIR/logs.json" "$RESULTS_SUBDIR/params.json"
git commit -m "Auto commit: add training results $RESULTS_SUBDIR"
git push origin "$BRANCH"

# === 上传训练结果到 Google Drive (rclone 配置名为 gdrive) ===
# 上传整个结果目录
echo "📤 Uploading results to Google Drive via rclone..."
rclone copy "$REPO_DIR/$RESULTS_SUBDIR" gdrive:nnunet_results/"$RESULTS_SUBDIR" --progress

# === 等待几秒确保上传完成 ===
sleep 30

# === 自动关闭 RunPod 实例 ===
if [[ -n "$RUNPOD_API_KEY" && -n "$RUNPOD_POD_ID" ]]; then
  echo "Shutting down RunPod instance $RUNPOD_POD_ID..."
  curl -X POST https://api.runpod.io/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: $RUNPOD_API_KEY" \
    -d '{
      "query": "mutation StopPod($podId: String!) { stopPod(input: { podId: $podId }) { podId status } }",
      "variables": { "podId": "'"$RUNPOD_POD_ID"'" }
    }'
else
  echo "⚠️ RUNPOD_API_KEY 或 RUNPOD_POD_ID 未设置，无法关闭实例"
fi
