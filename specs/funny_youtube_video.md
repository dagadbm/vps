I want to install Open Claw and set up my personal AI assistant.

>> Just use a VPS. It's like a one-click install.

>> Oh, I was just going to buy a Mac Mini.

>> No, you need to use a fresh Linux VPS. It's like what everybody does.

>> Continue.

Okay, that was easy. Uh, let's start by splitting up a server on your cloud VPS provider. You know, just a one vCPU, 4GB RAM, 100GB drive. Then you'll get a public IP and root SSH access. Then immediately we're under attack. I haven't even logged in yet.

>> Yeah, SSH scans started 12 seconds ago.

Now it's a fight against time. Do not install anything before securing your VPS root SSH access. So first we make sure we have the latest state of the internet on our VPS with apt update and apt upgrade. Why? Why? Our job is to keep our core running while other packages are changing theirs. Why? Then we'll install essential security and networking tools. Apt curl, apt wget, ufw, fail2ban, ca-certificates, gnupg. Why weren't these installed by default?

Well, that's because Linux was designed to be composable, transparent, minimal, scalable, and reusable in millions of environments. And it was not designed to be secure. Think about it. Secure for what? Well, for a server.

>> See, you can't answer that question.

>> For a server.

>> Second, we create a non-root user with a strong password. Then we delete password access and create an SSH key instead. 

>> I cannot use the password I use everywhere.

>> No, we need to harden the SSH tunnel. Now, verify the SSH config before logging yourself out. Restart with the new config. Then log out, log in with your SSH key again.

You didn't save your SSH key.

>> I was supposed to be paying attention.

>> We start from scratch.

Next firewall. This is an elimination diet. We block everything and then slowly reintroduce what we really need. And what do I need?

Well, that depends. Let's check what the tutorial says. The tutorial won't mention it, because I wrote that tutorial. We block all unsolicited traffic from the worldwide hostile web app, but we leave one door open: port 2222. Then we activate the firewall.

Why 2222?

>> Oh, it's just an arbitrary number. You could choose any.

>> 67.

>> No, the standard for arbitrary numbers is 2222.

Then we autoban IPs that guess passwords.

I thought we don't use passwords.

>> Well, that's today. But what about tomorrow? Then we configure the SSH jail for our port.

We start and verify, press ls -la 100 times. And now I will not get hacked.

>> No, I'm attacking it right now because it didn't enable automatic security updates and ensured the security origin is set.

Now, congrats. Your server can reboot itself at 3:00 a.m. Now, let's do some basic OS sanity. What kind of working environment would this be without a properly set time and date? Now let's control entropy. And now we get to the most interesting part. Install OpenClaw. Installing a private VPN mesh. Netbird, Tailscale. Verify if the wormhole actually opens. Now we allow SSH only through the VPN, but block SSH to our private VPN mesh. Public SSH is now gone. All public inbound traffic is now gone, except future IPv6 noise. So we disable IPv6 in UFW and apply kernel settings. No, just so we can sleep better. Reload. Verify.

So now we're already there to install the user package. This wasn't even the installation. But for this first we need to install its dependency NodeJS. We never trust Node versions shipped by distros. Install NodeJS from the official repo. Only then we install the user package directly from GitHub. But this, of course, doesn't work because we didn't install git. Now verify the repo isn't compromised by trusting GitHub and 900 random npm dependencies.

Meanwhile, we create a credentials directory because we don't dump production apps into home like crazy people. Don't we fix the directories' permissions? Why are they broken?

>> Broken is the de facto standard. Our start, restart and verify the user package with status. No, with doctor.

And now we are done. We configure the systemd service so if it breaks, it doesn't crash. You know, systemd is a controversial idea that hasn't been recognized widely in the Linux community, because initially it started as an init system. Then it became a scheduler, a debugger, a login manager, a device manager, a process manager. So if it crashes, basically everything crashes. But since 2015, basically every major Linux distribution has decided for this argument in 2015, and, uh, we lost. But there are still people who use Runit, OpenRC, or s6, but we don't talk to these people. But for now, systemd is a non‑optimal solution. Do you have anything to say?

Okay. So we create this small unit file. Activate and reactivate the service. Now make sure we're logging everything to observe runtime behavior. Disk protection, backups. Backups. And then run your application security audit if it has one.

I love it. I thought we did security already.

>> No, no, you don't do security. Security needs to live rent free in your mind at all times. And now you have the setup with no public SSH, no public web ports, and server only reachable via Tailscale. 98.1% uptime if you ignore the weekly kernel panics. And this was simple.

Yes, this was the Ubuntu version. Now I can show you how you would do this on Arch by the way.

No, no, no. Thank you. But now we're ready. Well, now you'd start configuring the application security measures so it doesn't start deleting your Gmail, leak your Ethereum wallet, and start joining online calls if somebody messages bendable commands to your Telegram bot.

What VPS are you running it on?

>> Oh, I'm just running it on an isolated Mac Mini.

What?

>> Oh, I didn't say you should follow as I do. Claude, give me a new agent. I don't like this agent. Give me a new agent. We didn't even get to talk about how to install Gentoo from source yet.

>> A lying agent. Please install OpenClaw simply so I can make automated fully market bets. Make no mistakes. Ah, this is no problem with an AWS EC2 instance. But first, we need to make sure to properly set up security groups and network access control lists. Have you heard about Kubernetes?

No.

>> No problem. I will teach you.

>> This video was sponsored by every service that is trying to make you run OpenClaw on their servers. They are the world's leading provider for that.