// Stops a running Rokumio+ simulator server (npm run sim:stop). Only touches a
// process that is listening on the simulator port AND is this repo's
// tools/simulator/server.py, so it never kills anything else on the machine.
const { execSync } = require('child_process');

const port = process.argv[2] || '6502';
let pids = [];
try {
    pids = execSync(`lsof -t -nP -iTCP:${port} -sTCP:LISTEN`, { encoding: 'utf8' }).split('\n').filter(Boolean);
} catch (e) {
    // lsof exits non-zero when nothing listens.
}
if (pids.length === 0) {
    console.log(`No simulator is running on port ${port}.`);
    process.exit(0);
}
for (const pid of pids) {
    const cmd = execSync(`ps -o command= -p ${pid}`, { encoding: 'utf8' }).trim();
    if (!cmd.includes('tools/simulator/server.py')) {
        console.log(`Port ${port} is used by something else (pid ${pid}: ${cmd}) — leaving it alone.`);
        continue;
    }
    process.kill(Number(pid), 'SIGTERM');
    console.log(`Stopped the simulator (pid ${pid}).`);
}
