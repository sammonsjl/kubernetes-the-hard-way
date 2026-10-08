// Creates Uptime Kuma's administrator, if it has none yet, and the monitors
// for Lab 12. Safe to run again: a monitor that already exists is left alone.
//
// Uptime Kuma has no command line for this. Its web page does everything over
// a WebSocket, and this script speaks the same protocol, using the client
// library Uptime Kuma ships for its own page. So it runs inside the pod:
//
//   kubectl exec -i -n uptime-kuma deployment/uptime-kuma -- env ... node - < apps/uptime-kuma-monitors.js
//
// It reads everything from the environment:
//   KUMA_USERNAME, KUMA_PASSWORD   the administrator to create or sign in as
//   CONTROL01, CONTROL02, CONTROL03, LOADBALANCER   the nodes' addresses
//   CLUSTER_DNS                    the cluster DNS Service's address

const { io } = require("socket.io-client");

const env = (name) => {
    if (!process.env[name]) {
        console.error(`${name} is not set`);
        process.exit(1);
    }
    return process.env[name];
};

// What every monitor has in common. A check every 20 seconds, the shortest
// Uptime Kuma allows, and no retries, so that a failure shows at once.
const base = {
    interval: 20,
    retryInterval: 20,
    resendInterval: 0,
    maxretries: 0,
    timeout: 10,
    notificationIDList: {},
    accepted_statuscodes: ["200-299"],
    conditions: [],
    kafkaProducerBrokers: [],
    kafkaProducerSaslOptions: { mechanism: "None" },
    rabbitmqNodes: [],
};

// The API servers answer /readyz to anyone, with a certificate signed by the
// lab's own CA, which Uptime Kuma has no reason to trust. ignoreTls skips the
// check of who signed it; the connection is still TLS.
const apiServer = (name, address) => ({
    ...base,
    type: "http",
    name,
    url: `https://${address}:6443/readyz`,
    method: "GET",
    maxredirects: 0,
    ignoreTls: true,
});

const monitors = [
    apiServer("API server on controlplane01", env("CONTROL01")),
    apiServer("API server on controlplane02", env("CONTROL02")),
    apiServer("API server on controlplane03", env("CONTROL03")),
    apiServer("API through the load balancer", env("LOADBALANCER")),
    {
        ...base,
        type: "dns",
        name: "Cluster DNS",
        hostname: "kubernetes.default.svc.cluster.local",
        dns_resolve_server: env("CLUSTER_DNS"),
        dns_resolve_type: "A",
        port: 53,
    },
    {
        ...base,
        type: "http",
        name: "Headlamp",
        url: "http://headlamp.headlamp.svc.cluster.local/",
        method: "GET",
        maxredirects: 0,
        ignoreTls: false,
    },
];

const socket = io("http://127.0.0.1:3001", { transports: ["websocket"] });

// One request and its answer, as a promise.
const ask = (event, ...args) =>
    new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`${event}: no answer`)), 15000);
        socket.emit(event, ...args, (answer) => {
            clearTimeout(timer);
            resolve(answer);
        });
    });

// The server sends "setup" to a new connection while it has no user at all.
let needsSetup = false;
socket.on("setup", () => {
    needsSetup = true;
});

// And it sends the list of monitors after a sign-in.
let existing = null;
socket.on("monitorList", (list) => {
    existing = Object.values(list).map((monitor) => monitor.name);
});

const fail = (message) => {
    console.error(message);
    process.exit(1);
};

socket.on("connect_error", (error) => fail(`Cannot connect: ${error.message}`));

socket.on("connect", async () => {
    try {
        const username = env("KUMA_USERNAME");
        const password = env("KUMA_PASSWORD");

        await new Promise((resolve) => setTimeout(resolve, 1000));

        if (needsSetup) {
            const created = await ask("setup", username, password);
            if (!created.ok) fail(`Creating ${username}: ${created.msg}`);
            console.log(`created the administrator ${username}`);
        }

        const login = await ask("login", { username, password, token: "" });
        if (!login.ok) fail(`Signing in as ${username}: ${login.msg}`);

        for (let i = 0; existing === null && i < 50; i++) {
            await new Promise((resolve) => setTimeout(resolve, 100));
        }

        for (const monitor of monitors) {
            if ((existing || []).includes(monitor.name)) {
                console.log(`exists   ${monitor.name}`);
                continue;
            }
            const added = await ask("add", monitor);
            if (!added.ok) fail(`Adding ${monitor.name}: ${added.msg}`);
            console.log(`added    ${monitor.name}`);
        }

        process.exit(0);
    } catch (error) {
        fail(error.message);
    }
});
