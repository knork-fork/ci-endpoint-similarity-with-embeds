# Endpoint Similarity with Embeds

Detects duplicate or semantically similar PHPDoc endpoint descriptions in controllers.

## Setup

Start the embedding API:

```bash
docker compose up -d --build --wait
```

## Running tests

```bash
bash run_tests.sh
```

Or check specific files:

```bash
bash test_similarity.sh Fixtures/Example_Similar.php
```

## Teardown

```bash
docker compose down
```
