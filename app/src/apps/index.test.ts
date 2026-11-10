import { expect, it } from "vitest";
import { apps, appPage, listApps } from ".";

const card = { title: "Runs", description: "Log a run." };

it("lists every app folder in this build, each with a page, a title, a description, and its address", () => {
  const folders = Object.keys(import.meta.glob("./*/app.json")).map((path) => path.split("/")[1]);

  expect(apps.map((app) => app.name)).toEqual(folders.sort());
  for (const app of apps) {
    expect(app.name, app.name).toMatch(/^[a-z0-9]+(-[a-z0-9]+)*$/);
    expect(app.title.trim(), app.name).not.toBe("");
    expect(app.description.trim(), app.name).not.toBe("");
    expect(app.href).toMatch(new RegExp(`^(?:/apps/${app.name}/|https://.+)$`));
    // A static app's page is the Worker's files, not a React page.
    expect(appPage(app.name) === null, app.name).toBe(!!app.static);
  }
});

it("lists a static app with no React page, and refuses one that has both", () => {
  const manifest = { ...card, static: true };
  expect(listApps({ "./runs/app.json": manifest }, [])).toEqual([{ name: "runs", ...card, href: "/apps/runs/", static: true }]);
  expect(() => listApps({ "./runs/app.json": manifest }, ["./runs/App.tsx"])).toThrow(
    'app/src/apps/runs: a static app has no App.tsx: remove it, or remove "static" from app.json.',
  );
});

it("opens a card with an https href at that address, and refuses any other href", () => {
  const manifest = { ...card, static: true, href: "https://app.example.com/" };
  expect(listApps({ "./runs/app.json": manifest }, [])).toEqual([{ name: "runs", ...card, href: "https://app.example.com/", static: true }]);
  for (const href of ["http://app.example.com/", "/apps/other/", "//app.example.com/", "javascript:alert(1)", "https:app.example.com", "", 3]) {
    expect(() => listApps({ "./runs/app.json": { ...manifest, href } }, []), String(href)).toThrow(
      'app/src/apps/runs: app.json\'s href must be an https address, such as "https://example.com/".',
    );
  }
});

it("opens the Relay Everything card at the shared server", () => {
  expect(apps.find((app) => app.name === "relay")?.href).toBe("https://app.relayeverything.com/");
});

it("finds no page for a folder that does not exist", () => {
  expect(appPage("nothing")).toBeNull();
});

it("sorts the list by name and keeps each card's words", () => {
  const list = listApps(
    { "./runs/app.json": card, "./a-b2/app.json": { title: "AB", description: "Two." } },
    ["./runs/App.tsx", "./a-b2/App.tsx"],
  );

  expect(list).toEqual([
    { name: "a-b2", title: "AB", description: "Two.", href: "/apps/a-b2/" },
    { name: "runs", title: "Runs", description: "Log a run.", href: "/apps/runs/" },
  ]);
});

it("fails on a folder name that is not an address, naming the folder", () => {
  for (const name of ["Runs", "my_runs", "runs-", "-runs", "my runs"]) {
    expect(() => listApps({ [`./${name}/app.json`]: card }, [`./${name}/App.tsx`]), name).toThrow(
      `app/src/apps/${name}: name the folder with lowercase letters, digits, and hyphens.`,
    );
  }
});

it("fails on a missing title, naming the folder", () => {
  for (const manifest of [{ description: "Log a run." }, { title: " ", description: "Log a run." }, { title: 3, description: "Log a run." }]) {
    expect(() => listApps({ "./runs/app.json": manifest }, ["./runs/App.tsx"])).toThrow(
      "app/src/apps/runs: app.json needs a title.",
    );
  }
});

it("fails on a missing description, naming the folder", () => {
  expect(() => listApps({ "./runs/app.json": { title: "Runs" } }, ["./runs/App.tsx"])).toThrow(
    "app/src/apps/runs: app.json needs a description.",
  );
});

it("fails on a page with no app.json, or an app.json with no page, naming the folder", () => {
  expect(() => listApps({}, ["./runs/App.tsx"])).toThrow("app/src/apps/runs: add app.json with a title and a description.");
  expect(() => listApps({ "./runs/app.json": card }, [])).toThrow("app/src/apps/runs: add App.tsx, exporting the page as `App`.");
});
