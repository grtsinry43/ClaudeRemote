import { watch, existsSync, statSync, type FSWatcher } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import { readdir } from 'fs/promises';

const PROJECTS_DIR = join(homedir(), '.claude', 'projects');
const SESSIONS_DIR = join(homedir(), '.claude', 'sessions');

/**
 * Watches ~/.claude/projects/ and ~/.claude/sessions/ for changes,
 * calls `onChange` with debouncing so the backend can push updates.
 */
export class FileWatcher {
  private watchers: FSWatcher[] = [];
  private watchedDirs = new Set<string>();
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private onChange: () => void;
  private debounceMs: number;

  constructor(onChange: () => void, debounceMs = 1000) {
    this.onChange = onChange;
    this.debounceMs = debounceMs;
  }

  async start() {
    // Watch the sessions dir (active process registry)
    if (existsSync(SESSIONS_DIR)) {
      this.watchDir(SESSIONS_DIR);
    }

    // Watch each project subdirectory for JSONL changes
    if (existsSync(PROJECTS_DIR)) {
      this.watchProjectsDir(PROJECTS_DIR);

      try {
        const projects = await readdir(PROJECTS_DIR, { withFileTypes: true });
        for (const entry of projects) {
          if (entry.isDirectory()) {
            this.watchDir(join(PROJECTS_DIR, entry.name));
          }
        }
      } catch {
        // ignore readdir errors
      }
    }
  }

  /**
   * Watch the top-level projects directory and dynamically add
   * watchers for newly created subdirectories.
   */
  private watchProjectsDir(dir: string) {
    try {
      const watcher = watch(dir, (eventType, filename) => {
        if (eventType === 'rename' && filename) {
          const fullPath = join(dir, filename);
          if (existsSync(fullPath)) {
            try {
              if (statSync(fullPath).isDirectory() && !this.watchedDirs.has(fullPath)) {
                this.watchDir(fullPath);
              }
            } catch {
              // stat may fail if the entry was removed between checks
            }
          }
        }
        if (filename && (filename.endsWith('.jsonl') || filename.endsWith('.json'))) {
          this.scheduleUpdate();
        }
      });
      this.watchers.push(watcher);
      this.watchedDirs.add(dir);
    } catch {
      // dir might not be watchable
    }
  }

  private watchDir(dir: string) {
    if (this.watchedDirs.has(dir)) return;
    try {
      const watcher = watch(dir, (eventType, filename) => {
        // Only care about .jsonl and .json files
        if (filename && (filename.endsWith('.jsonl') || filename.endsWith('.json'))) {
          this.scheduleUpdate();
        }
      });
      this.watchers.push(watcher);
      this.watchedDirs.add(dir);
    } catch {
      // dir might not be watchable
    }
  }

  private scheduleUpdate() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      this.onChange();
    }, this.debounceMs);
  }

  stop() {
    for (const w of this.watchers) {
      w.close();
    }
    this.watchers = [];
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
  }
}
