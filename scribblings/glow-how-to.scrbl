#lang scribble/manual

@(require "glow-code.rkt"
          "glow-docs.rkt"
          (for-label glow))

@title{Glow How-To}

@section{How to Get Help about @(Glow)}

For community help, join (our-discord-channel).

For commercial support, contact us directly at @(contact-email).

@section{How to Install @(Glow)}

@subsection{Easy Install for End-Users}

@emph{In the next few months}, we will compile @(Glow) fully to a single JavaScript file,
served from our website, that you can also copy and serve locally.

We will include a canary message on the website to warn about legal tampering;
but for serious deployment, you should check the JavaScript file and
verify it matches what auditors you trust did vouch for.

@subsection{Easy Install for Developers}

Currently, @(Glow) is available for installation on Linux and macOS.
To install, open a terminal and type or copy/paste the following command line:

@racketblock{
    curl -L https://glow-lang.org/install/glow-install | sh
}

This command will download about 2GB of programs and data using the
@hyperlink["https://nixos.org"]{Nix} package manager.
On Intel @racket[x86_64] it should download pre-compiled binary packages.
On other architectures, it may take quite some time to compile everything.
It may or may not work on Windows Subsystem for Linux (WSL).

@subsection{Easy Install Using Docker}

One alternative way to install @(Glow), that
@emph{will} run on Windows as well as on Linux and macOS,
is to use the @racket[mukn/glow:alpha] image from docker.
You may download the image with
@racketblock{
    docker pull mukn/glow:alpha
}

And then you may run it with
@racketblock{
    docker run -it mukn/glow:alpha bash
}

This will give you a shell in which to try running @racket[glow].

@subsection{Installing the Hard way}

See in our source repository
@hyperlink["https://gitlab.com/mukn/glow/-/blob/master/INSTALL.md"](INSTALL.md)
for full instructions on installing @(Glow)
for those who want to modify the language implementation itself.

If so, you should also read
@hyperlink["https://gitlab.com/mukn/glow/-/blob/master/HACKING.md"](HACKING.md)
for guidelines on making such modifications and rebuilding the software.
And, of course, join (our-discord-channel) to discuss with our developer community.
