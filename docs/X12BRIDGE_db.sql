CREATE TABLE "conversion_batches" (
  "id" varchar PRIMARY KEY,
  "name" varchar,
  "total_files" integer,
  "completed_files" integer,
  "failed_files" integer,
  "status" varchar,
  "inserted_at" timestamp,
  "updated_at" timestamp
);

CREATE TABLE "conversion_jobs" (
  "id" varchar PRIMARY KEY,
  "batch_id" varchar,
  "original_filename" varchar,
  "file_size" integer,
  "status" varchar,
  "json_result" text,
  "error_message" text,
  "processing_time_ms" integer,
  "progress" integer,
  "inserted_at" timestamp,
  "updated_at" timestamp
);

ALTER TABLE "conversion_jobs" ADD FOREIGN KEY ("batch_id") REFERENCES "conversion_batches" ("id");
