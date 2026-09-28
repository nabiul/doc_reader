import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from fastapi import BackgroundTasks, FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse


app = FastAPI(title="DocReader Office Converter", version="1.0.0")

SUPPORTED_EXTENSIONS = {".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".rtf"}
MAX_FILE_BYTES = int(os.getenv("MAX_FILE_BYTES", str(50 * 1024 * 1024)))
CONVERSION_TIMEOUT_SECONDS = int(os.getenv("CONVERSION_TIMEOUT_SECONDS", "120"))


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/convert")
async def convert(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
) -> FileResponse:
    extension = Path(file.filename or "").suffix.lower()
    if extension not in SUPPORTED_EXTENSIONS:
        raise HTTPException(status_code=415, detail="Unsupported document format")

    work_dir = Path(tempfile.mkdtemp(prefix="docreader-"))
    input_path = work_dir / f"input{extension}"
    output_dir = work_dir / "output"
    output_dir.mkdir()
    (work_dir / "home").mkdir()

    size = 0
    try:
        with input_path.open("wb") as destination:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_FILE_BYTES:
                    raise HTTPException(status_code=413, detail="Document is too large")
                destination.write(chunk)

        process = subprocess.run(
            [
                "libreoffice",
                "--headless",
                "--nologo",
                "--nodefault",
                "--nofirststartwizard",
                "--convert-to",
                "pdf",
                "--outdir",
                str(output_dir),
                str(input_path),
            ],
            capture_output=True,
            text=True,
            timeout=CONVERSION_TIMEOUT_SECONDS,
            env={**os.environ, "HOME": str(work_dir / "home")},
        )
        output_path = output_dir / "input.pdf"
        if process.returncode != 0 or not output_path.is_file():
            detail = process.stderr.strip() or process.stdout.strip() or "Conversion failed"
            raise HTTPException(status_code=422, detail=detail[-500:])

        background_tasks.add_task(shutil.rmtree, work_dir, True)
        download_name = f"{Path(file.filename or 'document').stem}.pdf"
        return FileResponse(
            output_path,
            media_type="application/pdf",
            filename=download_name,
            background=background_tasks,
        )
    except subprocess.TimeoutExpired as error:
        shutil.rmtree(work_dir, ignore_errors=True)
        raise HTTPException(status_code=504, detail="Conversion timed out") from error
    except HTTPException:
        shutil.rmtree(work_dir, ignore_errors=True)
        raise
    except Exception as error:
        shutil.rmtree(work_dir, ignore_errors=True)
        raise HTTPException(status_code=500, detail="Conversion failed") from error
    finally:
        await file.close()
