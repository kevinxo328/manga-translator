#!/usr/bin/env python3
"""Pack and upload quantized MLX model to HuggingFace Hub.

Creates a single zip archive from mlx_output/, computes its SHA256,
then uploads the archive + checksum file to HuggingFace.

Usage:
    source .venv/bin/activate
    cp .env.example .env && vi .env   # set HF_TOKEN and HF_REPO_ID
    python upload.py                  # upload model + card (default)
    python upload.py --model-only     # upload model zip only
    python upload.py --card-only      # upload MODEL_CARD.md only

Options:
    --repo-id       HuggingFace repo to create/update  (default: from .env)
    --model-dir     Local model directory              (default: ./mlx_output)
    --archive-name  Output archive filename            (default: model.zip)
    --card-path     Model card source file             (default: ./MODEL_CARD.md)
    --private       Create repo as private             (default: public)
    --model-only    Upload model zip only, skip card
    --card-only     Upload card only, skip model zip
"""

import argparse
import hashlib
import os
import sys
import zipfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
os.environ.setdefault("HF_HOME", str(SCRIPT_DIR / ".hf_cache"))


def load_dotenv(env_path: Path) -> None:
    """Load key=value pairs from .env into os.environ (skips comments and blanks)."""
    if not env_path.exists():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def create_archive(model_dir: Path, archive_path: Path) -> None:
    print(f"==> Packing {model_dir} → {archive_path.name}")
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_STORED) as zf:
        for file in sorted(model_dir.rglob("*")):
            if file.is_file():
                arcname = file.relative_to(model_dir)
                zf.write(file, arcname=str(arcname))
                print(f"   + {arcname}")
    size_mb = archive_path.stat().st_size / (1 << 20)
    print(f"   Archive size: {size_mb:.1f} MB")


def upload_model(api, repo_id: str, model_dir: Path, archive_name: str) -> None:
    if not model_dir.is_dir():
        print(f"Error: model directory not found: {model_dir}")
        sys.exit(1)

    archive_path = SCRIPT_DIR / archive_name
    create_archive(model_dir, archive_path)

    checksum = sha256_file(archive_path)
    checksum_path = SCRIPT_DIR / (archive_name + ".sha256")
    checksum_path.write_text(f"{checksum}  {archive_name}\n")
    print(f"==> SHA256: {checksum}")

    for upload_path in [archive_path, checksum_path]:
        print(f"==> Uploading {upload_path.name} ...")
        api.upload_file(
            path_or_fileobj=str(upload_path),
            path_in_repo=upload_path.name,
            repo_id=repo_id,
            repo_type="model",
            commit_message=f"Add {upload_path.name}",
        )

    archive_path.unlink()
    checksum_path.unlink()

    download_url = f"https://huggingface.co/{repo_id}/resolve/main/{archive_name}"
    print(f"\n==> Model uploaded. Add to ModelDownloadService:")
    print(f"    URL:    {download_url}")
    print(f"    SHA256: {checksum}")


def upload_card(api, repo_id: str, card_path: Path) -> None:
    if not card_path.is_file():
        print(f"Error: model card not found: {card_path}")
        sys.exit(1)

    print(f"==> Uploading {card_path.name} as README.md ...")
    api.upload_file(
        path_or_fileobj=str(card_path),
        path_in_repo="README.md",
        repo_id=repo_id,
        repo_type="model",
        commit_message="Update model card",
    )
    print(f"==> Card uploaded: https://huggingface.co/{repo_id}")


def main() -> None:
    load_dotenv(SCRIPT_DIR / ".env")

    parser = argparse.ArgumentParser(description="Pack and upload MLX model to HuggingFace")
    parser.add_argument(
        "--repo-id",
        default=os.environ.get("HF_REPO_ID", ""),
        help="HuggingFace repo ID, e.g. username/paddleocr-vl-manga-mlx",
    )
    parser.add_argument(
        "--model-dir",
        type=lambda p: Path(p).resolve(),
        default=SCRIPT_DIR / "mlx_output",
        help="Local model directory to pack (default: ./mlx_output)",
    )
    parser.add_argument(
        "--archive-name",
        default="model.zip",
        help="Archive filename (default: model.zip)",
    )
    parser.add_argument(
        "--card-path",
        type=lambda p: Path(p).resolve(),
        default=SCRIPT_DIR / "MODEL_CARD.md",
        help="Model card source file (default: ./MODEL_CARD.md)",
    )
    parser.add_argument(
        "--private",
        action="store_true",
        help="Create repo as private (default: public)",
    )

    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--model-only",
        action="store_true",
        help="Upload model zip only, skip card",
    )
    mode_group.add_argument(
        "--card-only",
        action="store_true",
        help="Upload card only, skip model zip",
    )

    args = parser.parse_args()

    if not args.repo_id:
        print("Error: --repo-id is required (or set HF_REPO_ID in .env).")
        sys.exit(1)

    token = os.environ.get("HF_TOKEN")
    if not token:
        print("Error: HF_TOKEN not set.")
        print("  1. Get a write-access token at https://huggingface.co/settings/tokens")
        print("  2. Add HF_TOKEN=hf_... to scripts/convert_model/.env")
        sys.exit(1)

    from huggingface_hub import HfApi

    api = HfApi(token=token)

    print(f"==> Creating/updating repo: {args.repo_id}")
    api.create_repo(repo_id=args.repo_id, repo_type="model", private=args.private, exist_ok=True)

    if args.card_only:
        upload_card(api, args.repo_id, args.card_path)
    elif args.model_only:
        upload_model(api, args.repo_id, args.model_dir, args.archive_name)
    else:
        upload_model(api, args.repo_id, args.model_dir, args.archive_name)
        upload_card(api, args.repo_id, args.card_path)


if __name__ == "__main__":
    main()
