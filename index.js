/**
 * SKA HOSTING - CORE SYSTEM
 * Created by SDGAMER
 * Do not remove credits.
 */

const express = require('express');
const Docker = require('dockerode');
const fs = require('fs-extra');
const multer = require('multer');
const path = require('path');
const app = express();

// --- CONFIG ---
const PORT = 8080;
const PANEL_NAME = "SKA HOSTING";
const docker = new Docker({ socketPath: '/var/run/docker.sock' });

// Setup Storage
const upload = multer({ dest: 'temp/' });
fs.ensureDirSync('./eggs');
fs.ensureDirSync('./servers');

app.use(express.urlencoded({ extended: true }));
app.use(express.static('public'));

// --- UI GENERATOR (Mobile Optimized) ---
const renderPage = (content) => `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${PANEL_NAME}</title>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;800&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #020617; --card: #0f172a; --accent: #6366f1; --text: #f8fafc; --danger: #ef4444; --success: #22c55e; }
        body { background: var(--bg); color: var(--text); font-family: 'Segoe UI', sans-serif; margin: 0; padding-bottom: 60px; }
        
        .navbar { background: rgba(15, 23, 42, 0.9); backdrop-filter: blur(10px); padding: 15px; border-bottom: 1px solid #1e293b; position: sticky; top: 0; z-index: 100; display: flex; justify-content: space-between; align-items: center; }
        .brand { font-family: 'JetBrains Mono', monospace; font-weight: 800; color: var(--accent); font-size: 18px; letter-spacing: -1px; }
        
        .container { padding: 20px; max-width: 600px; margin: 0 auto; }
        
        .card { background: var(--card); border: 1px solid #1e293b; padding: 20px; border-radius: 12px; margin-bottom: 15px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.3); }
        .card-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }
        .card h3 { margin: 0; font-size: 16px; font-weight: 600; }
        
        .btn { width: 100%; padding: 12px; border: none; border-radius: 8px; font-weight: bold; cursor: pointer; color: white; margin-top: 8px; font-size: 14px; transition: 0.2s; }
        .btn-primary { background: var(--accent); }
        .btn-danger { background: var(--danger); }
        .btn-success { background: var(--success); }
        
        input { width: 100%; padding: 12px; background: #020617; border: 1px solid #334155; color: white; border-radius: 8px; box-sizing: border-box; margin: 5px 0; }
        
        .status-badge { padding: 4px 8px; border-radius: 4px; font-size: 10px; text-transform: uppercase; font-weight: bold; letter-spacing: 1px; }
        .running { background: rgba(34, 197, 94, 0.2); color: var(--success); }
        .stopped { background: rgba(239, 68, 68, 0.2); color: var(--danger); }

        /* SECURITY: HARDCODED CREDIT */
        .footer { position: fixed; bottom: 0; left: 0; width: 100%; background: #000; padding: 12px; text-align: center; font-size: 11px; border-top: 1px solid #1e293b; color: #64748b; }
        .footer b { color: var(--accent); }
    </style>
</head>
<body>
    <div class="navbar">
        <div class="brand">${PANEL_NAME}</div>
        <a href="/" style="text-decoration:none; color:white; font-size:20px;">🏠</a>
    </div>

    <div class="container">
        ${content}
    </div>

    <div class="footer">
        Powered by ${PANEL_NAME} &bull; <b>Created by SDGAMER</b>
    </div>
</body>
</html>
`;

// --- ROUTES ---

// 1. DASHBOARD
app.get('/', async (req, res) => {
    let html = '';

    // Section: Import Egg
    html += `
    <div class="card" style="border-left: 3px solid var(--accent);">
        <div class="card-header"><h3>📥 Import Pterodactyl Egg</h3></div>
        <p style="font-size:12px; color:#94a3b8; margin-top:0;">Upload .json egg file to add support for Minecraft, Hytale, etc.</p>
        <form action="/import" method="POST" enctype="multipart/form-data">
            <input type="file" name="eggfile" required>
            <button class="btn btn-primary">Upload Egg</button>
        </form>
    </div>
    `;

    // Section: Active Servers
    html += `<h4 style="color:#94a3b8; margin-bottom:10px;">YOUR SERVERS</h4>`;
    
    try {
        const containers = await docker.listContainers({ all: true });
        if(containers.length === 0) html += `<p style="text-align:center; color:#475569; font-size:14px;">No servers running.</p>`;
        
        containers.forEach(c => {
            const name = c.Names[0].replace('/', '');
            const isRunning = c.State === 'running';
            html += `
            <div class="card">
                <div class="card-header">
                    <h3>${name}</h3>
                    <span class="status-badge ${isRunning ? 'running' : 'stopped'}">${c.State}</span>
                </div>
                <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
                    <form action="/server/start" method="POST"><input type="hidden" name="id" value="${c.Id}"><button class="btn btn-success">START</button></form>
                    <form action="/server/stop" method="POST"><input type="hidden" name="id" value="${c.Id}"><button class="btn btn-danger">STOP</button></form>
                </div>
                <form action="/server/delete" method="POST" onsubmit="return confirm('Delete this server?');">
                    <input type="hidden" name="id" value="${c.Id}">
                    <button class="btn" style="background:#334155; margin-top:10px;">DELETE</button>
                </form>
            </div>`;
        });
    } catch(e) { html += `<p style="color:red">Docker Error: ${e.message}</p>`; }

    // Section: Install New Server (From Imported Eggs)
    html += `<h4 style="color:#94a3b8; margin:20px 0 10px;">INSTALL NEW SERVER</h4>`;
    const eggs = await fs.readdir('./eggs');
    
    if(eggs.length === 0) {
        html += `<div class="card"><p style="text-align:center; color:#64748b;">No eggs imported yet.</p></div>`;
    } else {
        eggs.forEach(eggFile => {
            if(eggFile.endsWith('.json')) {
                const eggName = eggFile.replace('.json', '').toUpperCase();
                html += `
                <div class="card">
                    <div class="card-header"><h3>🥚 ${eggName}</h3></div>
                    <form action="/server/create" method="POST">
                        <input type="hidden" name="eggName" value="${eggFile}">
                        <input type="text" name="serverName" placeholder="Server Name (e.g. MySurvival)" required>
                        <button class="btn btn-primary">Create Server</button>
                    </form>
                </div>`;
            }
        });
    }

    res.send(renderPage(html));
});

// 2. IMPORT EGG LOGIC
app.post('/import', upload.single('eggfile'), async (req, res) => {
    if(req.file) {
        await fs.move(req.file.path, `./eggs/${req.file.originalname}`, { overwrite: true });
    }
    res.redirect('/');
});

// 3. CREATE SERVER LOGIC (Parses Pterodactyl Egg)
app.post('/server/create', async (req, res) => {
    try {
        const eggPath = `./eggs/${req.body.eggName}`;
        const eggData = await fs.readJson(eggPath);
        const serverName = req.body.serverName.replace(/[^a-zA-Z0-9]/g, '-'); // Clean name

        // INTELLIGENT PARSER: Finds the Docker Image from JSON
        let image = "ubuntu:latest"; 
        if(eggData.docker_images) {
            // Pterodactyl format usually has a map of images
            image = Object.values(eggData.docker_images)[0]; 
        } else if (eggData.image) {
            image = eggData.image;
        }

        // Pull Image First (Optional but good practice)
        // For now, we let createContainer pull it automatically

        await docker.createContainer({
            Image: image,
            name: serverName,
            Tty: true,
            OpenStdin: true,
            HostConfig: {
                PublishAllPorts: true, // Auto-maps ports for mobile ease
                RestartPolicy: { Name: 'unless-stopped' }
            }
        }).then(container => container.start());

        res.redirect('/');
    } catch (e) {
        res.send(renderPage(`<h3>Error Creating Server</h3><p>${e.message}</p><a href="/" class="btn btn-primary">Back</a>`));
    }
});

// 4. SERVER ACTIONS
app.post('/server/start', async (req, res) => {
    try { await docker.getContainer(req.body.id).start(); } catch(e){} res.redirect('/');
});
app.post('/server/stop', async (req, res) => {
    try { await docker.getContainer(req.body.id).stop(); } catch(e){} res.redirect('/');
});
app.post('/server/delete', async (req, res) => {
    try { 
        const c = docker.getContainer(req.body.id);
        await c.stop();
        await c.remove();
    } catch(e){} res.redirect('/');
});

// START
app.listen(PORT, () => console.log(`${PANEL_NAME} is live on Port ${PORT}`));
        
