export interface NanoidFunction {
  (length?: number): string;
  Batch(count: number, length?: number): string[];
  BatchBuffer(count: number, length?: number): Buffer;
}
