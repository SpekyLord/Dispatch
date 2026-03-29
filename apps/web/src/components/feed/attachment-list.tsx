type AttachmentListProps = {
  attachments: string[];
};

function assetLabel(url: string, index: number) {
  const lastSegment = url.split("/").pop()?.split("?")[0];
  return lastSegment ? decodeURIComponent(lastSegment) : `Attachment ${index + 1}`;
}

function fileExtension(label: string) {
  const parts = label.split(".");
  return parts.length > 1 ? parts.at(-1)?.toUpperCase() ?? "FILE" : "FILE";
}

function fileIcon(label: string) {
  const ext = label.split(".").at(-1)?.toLowerCase();
  if (!ext) return "description";
  if (["mp3", "wav", "m4a"].includes(ext)) return "audio_file";
  if (["ppt", "pptx"].includes(ext)) return "slideshow";
  if (["xls", "xlsx", "csv"].includes(ext)) return "table_chart";
  if (["doc", "docx", "txt"].includes(ext)) return "article";
  if (ext === "pdf") return "description";
  return "attach_file";
}

export function AttachmentList({ attachments }: AttachmentListProps) {
  if (attachments.length === 0) {
    return null;
  }

  return (
    <details className="group/attachments border-t border-[#ecd8cf] pt-4">
      <summary className="flex cursor-pointer list-none items-center gap-2 rounded-full border border-[#ecd8cf] bg-[#f7efe7] px-4 py-3 text-outline transition-colors hover:text-[#a14b2f]">
        <span className="material-symbols-outlined text-[18px] transition-transform group-open/attachments:rotate-90">
          chevron_right
        </span>
        <span className="text-[11px] font-bold uppercase tracking-widest">
          Attachments
        </span>
        <span className="ml-1 text-[10px] uppercase tracking-widest opacity-60">
          {attachments.length}
        </span>
      </summary>

      <div className="mt-4 space-y-2">
        {attachments.map((url, index) => {
          const label = assetLabel(url, index);
          const extension = fileExtension(label);
          const icon = fileIcon(label);

          return (
            <a
              key={`${url}-${index}`}
              href={url}
              target="_blank"
              rel="noreferrer"
              download
              className="group flex items-center gap-3 rounded-lg border border-[#ecd8cf] bg-[#fff8f3] p-4 transition-colors hover:bg-[#f7efe7]"
            >
              <span className="material-symbols-outlined text-outline transition-colors group-hover:text-[#a14b2f]">
                {icon}
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-xs font-semibold text-on-surface">{label}</p>
                <p className="text-[10px] uppercase tracking-wider text-outline">
                  {extension} document
                </p>
              </div>
              <span className="material-symbols-outlined text-sm text-outline">download</span>
            </a>
          );
        })}
      </div>
    </details>
  );
}
