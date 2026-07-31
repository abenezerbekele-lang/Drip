import {
  chmodSync,
  chownSync,
  existsSync,
  lstatSync,
  mkdirSync,
} from 'node:fs';
import path from 'node:path';

const runtimeUid = 1000;
const runtimeGid = 1000;

function prepareDatabaseDirectory() {
  const databasePath = process.env.DATABASE_PATH || '';
  if (
    databasePath === ':memory:' ||
    !path.isAbsolute(databasePath) ||
    path.basename(databasePath).length < 1
  ) {
    throw new Error(
      'The hosted container requires an absolute, persistent DATABASE_PATH.',
    );
  }

  const directory = path.dirname(databasePath);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const directoryStat = lstatSync(directory);
  if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink()) {
    throw new Error('The database volume mount is not a real directory.');
  }

  chownSync(directory, runtimeUid, runtimeGid);
  chmodSync(directory, 0o700);
  for (const file of [databasePath, `${databasePath}-wal`, `${databasePath}-shm`]) {
    if (!existsSync(file)) continue;
    const fileStat = lstatSync(file);
    if (!fileStat.isFile() || fileStat.isSymbolicLink()) {
      throw new Error('The database volume contains an unsafe file type.');
    }
    chownSync(file, runtimeUid, runtimeGid);
    chmodSync(file, 0o600);
  }
}

if (typeof process.getuid === 'function' && process.getuid() === 0) {
  prepareDatabaseDirectory();
  process.setgroups?.([]);
  process.setgid(runtimeGid);
  process.setuid(runtimeUid);
}

if (typeof process.getuid === 'function' && process.getuid() === 0) {
  throw new Error('The hosted service refused to run as root.');
}

await import('./src/server.js');
