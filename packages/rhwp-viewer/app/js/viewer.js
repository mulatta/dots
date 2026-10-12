(function () {
  "use strict";

  function onReady(callback) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback);
      return;
    }

    callback();
  }

  function statusMessage(container, message, className) {
    container.textContent = "";
    var paragraph = document.createElement("p");
    if (className) {
      paragraph.className = className;
    }
    paragraph.textContent = message;
    container.append(paragraph);
  }

  function fail(container, message) {
    statusMessage(container, message, "error");
  }

  function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function apiUrl(fileId) {
    if (window.OC && typeof window.OC.generateUrl === "function") {
      return window.OC.generateUrl(
        "/apps/rhwpviewer/api/files/{fileId}/convert",
        {
          fileId: fileId,
        },
      );
    }

    return (
      "/apps/rhwpviewer/api/files/" + encodeURIComponent(fileId) + "/convert"
    );
  }

  function validatePageUrl(url) {
    if (typeof url !== "string" || url === "") {
      throw new Error("Page URL is missing.");
    }

    var parsedUrl;
    try {
      parsedUrl = new URL(url, window.location.origin);
    } catch (error) {
      throw new Error("Page URL is invalid.");
    }

    if (parsedUrl.origin !== window.location.origin) {
      throw new Error("Page URL must stay on this server.");
    }

    return url;
  }

  function validateManifest(payload) {
    if (!isObject(payload)) {
      throw new Error("Conversion response is not an object.");
    }

    if (payload.status !== "ok") {
      if (
        payload.status === "error" &&
        typeof payload.error === "string" &&
        payload.error !== ""
      ) {
        throw new Error(payload.error);
      }
      throw new Error("Conversion did not complete successfully.");
    }

    if (payload.kind !== "svg") {
      throw new Error("Conversion response is not an SVG manifest.");
    }

    if (!Array.isArray(payload.pages)) {
      throw new Error("Conversion response does not contain pages.");
    }

    return payload.pages.map(function (page) {
      if (!isObject(page)) {
        throw new Error("Page entry is not an object.");
      }
      if (!Number.isInteger(page.index) || page.index < 0) {
        throw new Error("Page index is invalid.");
      }
      if (!Number.isInteger(page.bytes) || page.bytes < 0) {
        throw new Error("Page byte count is invalid.");
      }

      return {
        index: page.index,
        url: validatePageUrl(page.url),
      };
    });
  }

  function renderPages(container, pages) {
    container.textContent = "";

    if (pages.length === 0) {
      statusMessage(container, "No pages returned.");
      return;
    }

    pages.forEach(function (page) {
      var image = document.createElement("img");
      image.className = "rhwpviewer-page";
      image.src = page.url;
      image.alt = "Page " + (page.index + 1);
      image.loading = "lazy";
      image.decoding = "async";
      container.append(image);
    });
  }

  function startViewer() {
    var root = document.getElementById("rhwpviewer-root");
    if (!root) {
      return;
    }

    var fileId = root.dataset.fileId;
    if (!fileId) {
      return;
    }

    var container = document.getElementById("rhwpviewer-pages");
    if (!container) {
      container = document.createElement("div");
      container.id = "rhwpviewer-pages";
      container.setAttribute("aria-live", "polite");
      root.append(container);
    }

    statusMessage(container, "Loading pages…");

    fetch(apiUrl(fileId), {
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
      },
    })
      .then(function (response) {
        if (!response.ok) {
          throw new Error(
            "Conversion request failed with HTTP " + response.status + ".",
          );
        }
        return response.json();
      })
      .then(function (payload) {
        renderPages(container, validateManifest(payload));
      })
      .catch(function (error) {
        fail(container, "Could not load viewer pages: " + error.message);
      });
  }

  onReady(startViewer);
})();
