import pg from 'pg';
import { config } from './config.ts';

// Small pool: the whole server has 1 GB of memory.
export const pool = new pg.Pool({ connectionString: config.databaseUrl, max: 8 });

export type Queryable = Pick<pg.Pool, 'query'> | pg.PoolClient;

export async function q<T = any>(sql: string, params: unknown[] = [], db: Queryable = pool): Promise<T[]> {
  const res = await db.query(sql, params as any[]);
  return res.rows as T[];
}

export async function one<T = any>(sql: string, params: unknown[] = [], db: Queryable = pool): Promise<T | undefined> {
  return (await q<T>(sql, params, db))[0];
}

export async function tx<T>(fn: (c: pg.PoolClient) => Promise<T>): Promise<T> {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const out = await fn(c);
    await c.query('COMMIT');
    return out;
  } catch (e) {
    await c.query('ROLLBACK');
    throw e;
  } finally {
    c.release();
  }
}
