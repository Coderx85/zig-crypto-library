declare module "node-gyp-build" {
  function gypBuild(dir: string): any;
  export = gypBuild;
}
