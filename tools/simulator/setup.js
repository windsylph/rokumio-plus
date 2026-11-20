// Prepares tools/simulator/web for `npm run sim`: copies the brs-engine
// simulator (browser build + SceneGraph extension) out of node_modules and the
// freshly built channel package next to index.html.
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const web = path.join(__dirname, 'web');
const mod = (...p) => path.join(root, 'node_modules', ...p);

function copy(from, to) {
    if (!fs.existsSync(from)) {
        console.error(`Missing ${path.relative(root, from)} — run "npm install" first.`);
        process.exit(1);
    }
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
}

copy(mod('brs-engine', 'lib', 'brs.api.js'), path.join(web, 'lib', 'brs.api.js'));
copy(mod('brs-engine', 'lib', 'brs.worker.js'), path.join(web, 'lib', 'brs.worker.js'));
copy(mod('brs-scenegraph', 'lib', 'brs-sg.js'), path.join(web, 'lib', 'brs-sg.js'));
// The SceneGraph bundle's common.zip is a superset of the engine's (it adds the
// SceneGraph fonts), so it is the one the page loads.
copy(mod('brs-scenegraph', 'assets', 'common.zip'), path.join(web, 'assets', 'common.zip'));
copy(path.join(root, 'dist', 'rokumio-client.zip'), path.join(web, 'app.zip'));
console.log('Simulator ready.');
