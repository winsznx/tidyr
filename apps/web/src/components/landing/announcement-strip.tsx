export function AnnouncementStrip() {
  return (
    <div className="bg-(--color-terminal) py-2 text-center text-xs text-white">
      <span className="inline-flex items-center gap-2">
        <span
          className="inline-block h-1.5 w-1.5 rounded-full bg-(--color-accent-wash)"
          aria-hidden="true"
        />
        Live on Monad mainnet — chain 143
      </span>
    </div>
  );
}
