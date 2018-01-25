import rpi_babel from 'rollup-plugin-babel'
const plugins = [jsy_plugin()]

export default [
  { input: 'code/octree.jsy', 
    output: { name: 'octree', file: `dist/octree.js`, format: 'cjs'},
    external: [], plugins },
  { input: 'code/octree_tests.jsy', 
    output: { name: 'octree_tests', file: `dist/octree_tests.js`, format: 'cjs'},
    external: [], plugins },
]

function jsy_plugin() {
  const jsy_preset = [ 'jsy/lean', { no_stage_3: true, modules: false } ]
  return rpi_babel({
    exclude: 'node_modules/**',
    presets: [ jsy_preset ],
    plugins: [],
    babelrc: false }) }
