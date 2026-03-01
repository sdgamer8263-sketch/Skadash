const express = require('express');
const Docker = require('dockerode');
const fs = require('fs-extra');
const multer = require('multer');
const path = require('path');
const app = express();
const docker = new Docker({ socketPath: '/var/run/docker.sock' });

// CONFIGURATION
const PORT = 8080;
const PANEL_NAME = "SKA HOSTING";
const upload = multer({ dest: 'uploads/' });

// Ensure Eggs Directory Exists
fs.ensureDirSync('./eggs');

app.use(express.urlencoded({ extended: true }));

// --- STYLE & UI ---
const getHeader = () => `
<!DOCTYPE html>
<html>
<head>
    <title>${PANEL_NAME}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        :root { --bg: #09090b; --card: #18181b; --primary: #6366f1; --text: #e4e4e7; }
        body { background: var(--bg); color: var(--text); font-family: sans-serif; margin: 0; padding: 20px; }
        .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #27272a; padding-bottom: 20px; }
        .card { background: var(--card); padding: 20px; border-radius: 8px; border: 1px solid #27272a; margin-bottom: 15px; }
        .btn { background: var(--primary); color: white; border: none; padding: 10px 15px; border-radius: 5px; cursor: pointer; font-weight: bold; }
        .input { background: #000; border: 1px solid #333; color: white; padding: 10px; width: 100%; border-radius: 5px; margin-bottom: 10px; }
        footer { text-align: center; margin-top: 50px; opacity: 0.5; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h2>${PANEL_NAME}</h2>
        <a href="/"><button class="btn">Dashboard</button></a>
    </div>
    <br>
`;

// --- ROUTES ---

// 1. Dashboard (Server List & Import)
app.get('/', async (req, res) => {
    let html = getHeader();
    
    // Import Section
    html += `
    <div class="card">
        <h3>📥 Import Pterodactyl Egg</h3>
        <form action="/import" method="post" enctype="multipart/form-data">
            <input type="file" name="eggfile" class="input" required>
            <button type="submit" class="btn">Upload Egg</button>
        </form>
    </div>
    <h2>Available Servers</h2>
    `;

    // List Eggs to Install
    const files = await fs.readdir('./eggs');
    files.forEach(file => {
        if(file.endsWith('.json')) {
            html += `
            <div class="card" style="border-left: 4px solid #6366f1;">
                <h3>🥚 ${file.replace('.json', '')}</h3>
                <form action="/deploy" method="POST">
                    <input type="hidden" name="egg" value="${file}">
                    <input type="text" name="name" placeholder="Server Name" class="input" required>
                    <button class="btn">Install This Server</button>
                </form>
            </div>`;
        }
    });

    // List Running Containers
    const containers = await docker.listContainers({ all: true });
    html += `<h2>Active Containers</h2>`;
    containers.forEach(c => {
        html += `<div class="card"><h3>${c.Names[0]}</h3><p>Status: ${c.State}</p></div>`;
    });

    // Hardcoded Credit
    html += `<footer>Panel System by ${PANEL_NAME} | <b>Created by SDGAMER</b></footer></body></html>`;
    res.send(html);
});

// 2. Import Logic
app.post('/import', upload.single('eggfile'), async (req, res) => {
    try {
        const oldPath = req.file.path;
        const newPath = `./eggs/${req.file.originalname}`;
        await fs.move(oldPath, newPath, { overwrite: true });
        res.redirect('/');
    } catch (e) { res.send("Upload Failed: " + e.toString()); }
});

// 3. Deploy Logic (Reads Pterodactyl Egg)
app.post('/deploy', async (req, res) => {
    try {
        const eggContent = await fs.readJson(`./eggs/${req.body.egg}`);
        const serverName = req.body.name.replace(/\s+/g, '-');
        
        // Pterodactyl Egg parsing logic (Simplified)
        let dockerImage = "ubuntu:latest"; 
        if(eggContent.docker_images) {
            dockerImage = Object.values(eggContent.docker_images)[0];
        }

        await docker.createContainer({
            Image: dockerImage,
            name: serverName,
            Tty: true,
            HostConfig: { PortBindings: { '25565/tcp': [{ HostPort: '25565' }] } } // Auto Port 25565
        }).then(container => container.start());

        res.redirect('/');
    } catch (e) { res.send("Deploy Error: " + e.toString()); }
});

app.listen(PORT, () => console.log(`${PANEL_NAME} Started on Port ${PORT}`));
