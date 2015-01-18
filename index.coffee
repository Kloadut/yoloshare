#!/usr/bin/env coffee

fs = require 'fs'
path = require 'path'
program = require 'commander'
https = require 'https'
pem = require 'pem'
randtoken = require 'rand-token'
url = require 'url'
externalIp = require 'externalip'
progress = require 'progress-stream'
ProgressBar = require 'progress'
mime = require 'mime'
spawn = require('child_process').spawn
log = require('printit')
    prefix: 'yoloShare'


process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0"


launchPwnatServer = ->

    externalIp (err, ip) ->
        log.info "IP address is #{ip}"

    high = 50000
    low  = 35000
    port = Math.floor(Math.random() * (high - low) + low)
    pwnat = spawn 'pwnat', [ '-s', '-v', port ]

    log.info "Launching pwnat on port #{port}"

    pwnat.stdout.on 'data', (data) ->
        console.log data

    pwnat.on 'close', (code) ->
        if code isnt 0
            log.error "pwnat exited with status #{code}"
        else
            log.info "pwnat exited"

launchPwnatClient = (ip, port) ->

    pwnat = spawn 'pwnat', [ '-c', '-v', 34999, ip, port, '127.0.0.1', 34999 ]

    log.info "Connecting to pwnat tunnel on #{ip}:#{port}"

    pwnat.stdout.on 'data', (data) ->
        log.info "pwnat: #{data}"

    pwnat.on 'close', (code) ->
        if code isnt 0
            log.error "pwnat exited with status #{code}"
        else
            log.info "pwnat exited"


sendFile = (file, email) ->
    launchPwnatServer()

    # Generate SSL certificate
    pem.createCertificate
        days: 1
        selfSigned: true
    , (err, res) ->
        options =
            key: res.clientKey
            cert: res.certificate

        pem.getFingerprint res.certificate, (err, res) ->
            log.info "Fingerprint of the certificate: #{res.fingerprint}"

        # Generate one-time token
        token = randtoken.generate(16)
        log.info "Token is #{token}"

        server = https.createServer options, (req, res) ->
            uri = url.parse(req.url).pathname
            if uri is "/#{token}"
                filePath = path.resolve file
                fs.stat filePath, (err, stats) ->
                    if err? or not stats.isFile()
                        log.error "You didn't indicate an actual file to send"
                        process.exit 1

                    bar = new ProgressBar "  Uploading #{filePath} [:bar] :percent :etas",
                        complete: '='
                        incomplete: ' '
                        width: 20
                        total: stats.size

                    str = progress { length: stats.size, time: 100 }

                    str.on 'progress', (data) ->
                        bar.tick data.delta

                    res.writeHead 200,
                        'content-type': mime.lookup file
                        'content-length': stats.size
                        'x-filename': path.basename file
                    stream = fs.createReadStream filePath
                    stream.pipe(str).pipe(res)
            else
                res.writeHead 401
                res.end()

        server.listen 34999


getFile = (ip, port, token) ->
    launchPwnatClient(ip, port)
    setTimeout ( -> downloadFile token), 3000


downloadFile = (token) ->
    options =
        hostname: '127.0.0.1'
        port: 34999
        path: "/#{token}"
        method: 'GET'

    req = https.request options, (res) ->
        fileName = res.headers['x-filename']
        if res.statusCode isnt 200 or not fileName
            log.error "Nope"
            process.exit 1

        len = parseInt(res.headers['content-length'], 10)
        bar = new ProgressBar "  Downloading #{fileName} [:bar] :percent :etas",
            complete: '='
            incomplete: ' '
            width: 20
            total: len

        stream = fs.createWriteStream fileName
        res.on 'data', (data) ->
            stream.write data
            bar.tick data.length

        res.on 'end', ->
            log.info "File #{fileName} successfully downloaded"

    req.end()

    req.on 'error', (err) ->
        log.error err
        setTimeout ( -> downloadFile token), 3000

program
    .command 'send-file <file>'
    .description 'Send a file to someone'
    .option '-m, --email <email>', 'Send an email with all the information needed to download the file to a specific address'
    .action sendFile

program
    .command 'get-file <ip> <port> <token>'
    .description 'Get a file from someone'
    .action getFile

if not module.parent
    program.parse process.argv

unless process.argv.slice(2).length
    program.outputHelp()

