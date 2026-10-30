export default function DashboardLoading() {
  return (
    <div className="space-y-4 lg:space-y-6" aria-busy="true" aria-live="polite">
      <div className="flex items-end justify-between gap-3">
        <div className="space-y-2">
          <div className="skeleton h-2.5 w-16" />
          <div className="skeleton h-7 w-40" />
        </div>
        <div className="skeleton h-3 w-28" />
      </div>

      <div className="panel overflow-hidden">
        <div className="grid grid-cols-2 divide-x divide-border border-b border-border lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, index) => (
            <div key={index} className="space-y-2 p-4">
              <div className="skeleton h-2.5 w-20" />
              <div className="skeleton h-7 w-28" />
              <div className="skeleton h-2.5 w-24" />
            </div>
          ))}
        </div>
        <div className="p-4">
          <div className="skeleton h-56 w-full" />
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <div className="panel p-4">
          <div className="skeleton h-4 w-32" />
          <div className="mt-4 space-y-2">
            {Array.from({ length: 4 }).map((_, index) => (
              <div key={index} className="skeleton h-10 w-full" />
            ))}
          </div>
        </div>
        <div className="panel p-4">
          <div className="skeleton h-4 w-28" />
          <div className="mt-4 space-y-2">
            {Array.from({ length: 4 }).map((_, index) => (
              <div key={index} className="skeleton h-10 w-full" />
            ))}
          </div>
        </div>
      </div>

      <span className="sr-only">Loading your journal</span>
    </div>
  )
}
