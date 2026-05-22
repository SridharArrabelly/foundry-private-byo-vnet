"""
setup_aisearch_index.py

Creates an AI Search index, reads .docx files from the data/ folder,
chunks the content, generates embeddings via Azure OpenAI (text-embedding-3-large),
and uploads the chunks to the AI Search index.

Usage:
    pip install -r scripts/requirements.txt
    python scripts/setup_aisearch_index.py
"""

import os
import sys
import glob
from pathlib import Path
from dotenv import load_dotenv
from docx import Document
from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex,
    SearchField,
    SearchFieldDataType,
    SimpleField,
    SearchableField,
    VectorSearch,
    HnswAlgorithmConfiguration,
    VectorSearchProfile,
)
from openai import AzureOpenAI

# Load .env from project root
env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=env_path)

# --- Configuration from .env ---

AI_SEARCH_ENDPOINT = os.environ.get("AI_SEARCH_ENDPOINT")
AI_FOUNDRY_ENDPOINT = os.environ.get("AI_FOUNDRY_ENDPOINT")
INDEX_NAME = os.environ.get("AI_SEARCH_INDEX_NAME", "documents-index")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-3-large")
EMBEDDING_DIMENSIONS = int(os.environ.get("EMBEDDING_DIMENSIONS", "3072"))
CHUNK_SIZE = int(os.environ.get("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.environ.get("CHUNK_OVERLAP", "200"))
DATA_FOLDER = os.path.join(os.path.dirname(__file__), "..", "data")


def validate_config():
    """Ensure required environment variables are set."""
    if not AI_SEARCH_ENDPOINT:
        print("ERROR: Set AI_SEARCH_ENDPOINT environment variable")
        sys.exit(1)
    if not AI_FOUNDRY_ENDPOINT:
        print("ERROR: Set AI_FOUNDRY_ENDPOINT environment variable")
        sys.exit(1)


def extract_text_from_docx(file_path: str) -> str:
    """Extract all text from a .docx file."""
    doc = Document(file_path)
    return "\n".join(para.text for para in doc.paragraphs if para.text.strip())


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Split text into overlapping chunks."""
    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size
        chunks.append(text[start:end])
        start += chunk_size - overlap
    return [c for c in chunks if c.strip()]


def create_index(index_client: SearchIndexClient):
    """Create the search index with vector field for embeddings."""
    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True, filterable=True),
        SearchableField(name="content", type=SearchFieldDataType.String),
        SimpleField(name="source_file", type=SearchFieldDataType.String, filterable=True),
        SimpleField(name="chunk_index", type=SearchFieldDataType.Int32, filterable=True),
        SearchField(
            name="content_vector",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=EMBEDDING_DIMENSIONS,
            vector_search_profile_name="embedding-profile",
        ),
    ]

    vector_search = VectorSearch(
        algorithms=[HnswAlgorithmConfiguration(name="hnsw-config")],
        profiles=[
            VectorSearchProfile(name="embedding-profile", algorithm_configuration_name="hnsw-config")
        ],
    )

    index = SearchIndex(name=INDEX_NAME, fields=fields, vector_search=vector_search)

    print(f"Creating index '{INDEX_NAME}'...")
    index_client.create_or_update_index(index)
    print(f"Index '{INDEX_NAME}' created successfully.")


def generate_embeddings(openai_client: AzureOpenAI, texts: list[str]) -> list[list[float]]:
    """Generate embeddings for a list of texts using the configured embedding model."""
    response = openai_client.embeddings.create(input=texts, model=EMBEDDING_MODEL)
    return [item.embedding for item in response.data]


def index_documents(search_client: SearchClient, openai_client: AzureOpenAI):
    """Read docx files, chunk, embed, and upload to search index."""
    docx_files = glob.glob(os.path.join(DATA_FOLDER, "*.docx"))

    if not docx_files:
        print(f"No .docx files found in {DATA_FOLDER}")
        sys.exit(1)

    print(f"Found {len(docx_files)} .docx file(s) to index.")

    all_documents = []
    doc_id = 0

    for file_path in docx_files:
        filename = os.path.basename(file_path)
        print(f"  Processing: {filename}")

        text = extract_text_from_docx(file_path)
        chunks = chunk_text(text)
        print(f"    → {len(chunks)} chunks")

        # Generate embeddings in batches of 16
        for batch_start in range(0, len(chunks), 16):
            batch = chunks[batch_start : batch_start + 16]
            embeddings = generate_embeddings(openai_client, batch)

            for i, (chunk, embedding) in enumerate(zip(batch, embeddings)):
                all_documents.append(
                    {
                        "id": str(doc_id),
                        "content": chunk,
                        "source_file": filename,
                        "chunk_index": batch_start + i,
                        "content_vector": embedding,
                    }
                )
                doc_id += 1

    # Upload in batches of 100
    print(f"Uploading {len(all_documents)} chunks to index...")
    for batch_start in range(0, len(all_documents), 100):
        batch = all_documents[batch_start : batch_start + 100]
        search_client.upload_documents(documents=batch)
    print("Upload complete!")


def main():
    validate_config()

    credential = DefaultAzureCredential()

    # Search clients
    index_client = SearchIndexClient(endpoint=AI_SEARCH_ENDPOINT, credential=credential)
    search_client = SearchClient(endpoint=AI_SEARCH_ENDPOINT, index_name=INDEX_NAME, credential=credential)

    # OpenAI client (Azure)
    openai_client = AzureOpenAI(
        azure_endpoint=AI_FOUNDRY_ENDPOINT,
        azure_ad_token_provider=lambda: credential.get_token("https://cognitiveservices.azure.com/.default").token,
        api_version="2024-10-21",
    )

    # Step 1: Create index
    create_index(index_client)

    # Step 2: Chunk docs and upload with embeddings
    index_documents(search_client, openai_client)

    print(f"\n✅ Done! Index '{INDEX_NAME}' is ready with {INDEX_NAME} chunks indexed.")


if __name__ == "__main__":
    main()
