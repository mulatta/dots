import {
  DefaultType,
  FileType,
  Permission,
  registerFileAction,
} from "@nextcloud/files";
import { t } from "@nextcloud/l10n";
import { generateUrl } from "@nextcloud/router";

const APP_ID = "rhwpviewer";
const SUPPORTED_EXTENSIONS = ["hwp", "hwpx"];

function iconSvg() {
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true"><path fill="currentColor" d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zm-1 1.5L18.5 9H13zM8 13h8v1.5H8zm0 3h8v1.5H8zm0-6h3v1.5H8z"/></svg>';
}

function normalizeExtension(extension) {
  if (typeof extension !== "string") {
    return "";
  }

  return extension.toLowerCase().replace(/^\./, "");
}

function extensionForNode(node) {
  const extension = normalizeExtension(node.extension);
  if (extension !== "") {
    return extension;
  }

  if (typeof node.basename !== "string") {
    return "";
  }

  const index = node.basename.lastIndexOf(".");
  if (index === -1) {
    return "";
  }

  return normalizeExtension(node.basename.slice(index + 1));
}

function fileIdForNode(node) {
  if (Number.isInteger(node.fileid) && node.fileid > 0) {
    return node.fileid;
  }

  if (typeof node.id === "string" && /^\d+$/.test(node.id)) {
    return Number(node.id);
  }

  return null;
}

function isSupportedNode(node) {
  if (!node || node.type !== FileType.File) {
    return false;
  }

  if ((node.permissions & Permission.READ) === 0) {
    return false;
  }

  if (fileIdForNode(node) === null) {
    return false;
  }

  return SUPPORTED_EXTENSIONS.includes(extensionForNode(node));
}

registerFileAction({
  id: "rhwpviewer-open",
  order: 20,
  default: DefaultType.DEFAULT,
  displayName: () => t(APP_ID, "Open in RHWP Studio"),
  iconSvgInline: iconSvg,
  enabled: ({ nodes }) => nodes.length === 1 && isSupportedNode(nodes[0]),
  exec: async ({ nodes }) => {
    const fileId = fileIdForNode(nodes[0]);
    if (fileId === null) {
      return false;
    }

    window.location.href = generateUrl("/apps/rhwpviewer/edit/{fileId}", {
      fileId,
    });
    return null;
  },
});
