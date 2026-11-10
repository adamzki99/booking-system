FROM python:3.11-slim

# Install dependencies and strands-decider directly from GitHub for the latest version
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir "strands-decider @ git+https://github.com/strands-labs/strands-decider" huggingface_hub

# Expose the port for the HTTP server
EXPOSE 8000

# Start the server and download the desired model (e.g. 2B or 12B variant)
CMD ["strands-decider", "serve", "StrandsAgents/strands-decider-2B-qwen3.5-v1-2610", "--host", "0.0.0.0", "--port", "8000", "--device", "cpu"]