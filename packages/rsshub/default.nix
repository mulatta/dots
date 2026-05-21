{ rsshub }:

rsshub.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    substituteInPlace lib/utils/playwright.ts \
      --replace-fail \
        'scheduleClose(browser);' \
        'scheduleClose(browser, Number.parseInt(process.env.PLAYWRIGHT_CLOSE_TIMEOUT ?? "30000", 10) || 30000);'

    cp -R --no-preserve=mode ${./routes}/. lib/routes/
    find lib/routes \( -name '*.test.ts' -o -name '*.test.tsx' \) -delete
    mkdir -p lib/custom-tests
    cp -R ${./tests}/. lib/custom-tests/
  '';
})
