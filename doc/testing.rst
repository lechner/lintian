Lintian Testing Manual

A maintainer's Best Friend

Lintian provides private packaging advice to thousands of
contributors. Many are newbies who want to give back to the great free
operating systems, others are hardened pros who have somehow figured
out how to contribute for long periods of time without being paid for
it. Either way, Lintian is their best friend.

Debian has become so complicated that it is more or less impossible to
know all the recommendations for proper packaging by heart. Instead
people fire up Lintian. Actually, most of the time, it runs
automatically. You really cannot escape it. It's on the
tracker. Various builders can run it, or do so by default.

The first time you see it, you go: What is this? Yet over time,
Lintian invasive, incessant voice appears less judgmental more
benevolent. It is not ceremonious. The most exciting aspect of
Lintian's tag output is the color, if you are lucky to sit at a
terminal while it runs. Otherwise, you quietly try to decipher the
compact tag names later to figure out what happened.

The messages are curt nudges, issued without apologies. Lintian is ice
cold. Plus, it is always right. We look at the list of tags and go,
that can't be right. Yet then we inspect the tag description, do some
more research online and find some related expert postings in mailing
lists and dedicated websites. A shock. Lintian is right. It's not a
false positve. How could I forget about it. How did Lintian know. It's
a stupid computer!

These feelings are multiplied if we turn on the pedantic setting..

Love it or hate it, Lintian has this amazing repertoire of analytical
skills. It tells us things about our packages, about Debian, and
sometimes about ourselves that we did not know, or did not want to
know. Sometimes, it feels like it's psychologist talking, sotto
voce. Whew, it's just an info tag. No big deal. At other times,
Lintian speaks with great bearing and authority. Insecure URL. No
doubt about that! Bam. Let's fix it.

At still other times, Lintian supports its obscure findings with the
biggest hammer of all: It'a against policy. Policy? How about reason?
I am a fine maintainer, thank you very much! The range of emotion can
be great as we react to this whimpy, dwarf-like being called Lintian
that has the charm of a chess computer. Yet, we do exactly as it
says. The vast majority of tags are valid and get fixed. Sometimes, we
file bug reports because Lintian seems to jhave gotten it wrong. "This
does not apply to me." Often, it actually does. No, it's not a false
positive.

It's been said about Google that that's where you go when you want to
talk to a computer; visit Facebook to talk to fellow human
beings. Actually, Google is a luxury. At its best, it answers all your
questions. Lintian doesn't. Lintian just accuses. In some ways, it is
like Satan, the heavenly prosecutor who whispers your misdeeds into
someone's ear. "Look, that fellow over there did not follow your law."

Which brings us back to policy. It's been said that Lintian is the
Debian policy's "programmatic embodiment". An enforcer. Now, that's
not very kind. It's also not very accurate. Most tags are actually not
supported, or required, by policy. They are either based on experience
or constitute a good piece of advice that someone wanted to pass
on. "The package ships the two (or more) files with the exact same
contents. Duplicates can often be replaced with symlinks..." Duh! Or
my personal favorite, "The documentation directory for this package
contains an empty file." Really?

Lintian's seemingly countless remarks can be tiring. The tag
descriptions never vary, and we never warm up to them. Oh no, not that
tag again. Or, yes, I know how to fix that one. There is no charm, no
decorum. Nothing. Lintian is like the cheap version of an expert, but
it works twenty-four hours a day.

So why does Lintian have so much authority? It's because its remarks
are honed by thousands of contributors on tens of thousands of
packages. As a group, we are getting it right. False positives do
occur, and are usually corrected when they are reported. Over time,
Lintian ends up being a pretty good system. It's a voice of reason in
an era of boundless individuality. Except, there is no freedom of
expression with Lintian. In fact, there is no freedom of opinion with
Lintian. It's a computer. It's our computer. It's us.

Once we engage with our collective wisdom, we usually lose. There are
few more humbling experiences than being a Lintian developer. We are
surrounded on all sides. First of all, we manage a collective
repository of good advice that we know relatively little about. It's
simply not possible to know about all the minutia of ELF files or
systemd services and so on. Second, there are the angry hoardes of
developers who feel slighted by a tag's wording or its priority. Or
maybe, it is a false positive. And third, we too as maintainers have
to contend with Lintian stone cold attitude. Why is that check not
working? That's where testing comes in.

Wheh it comes to making tags work well and also make them defensible
toward others, there is no greater tool than testing. Our test suite
offers a completely simulated packaging environment. Best of all,
there are standard templates in the background that serve as a
skeleton before the test files are superimposed. As a result, the test
files usually illustrate immediately what the test is about. Many
times, there are no files at all.

The templating system will replace a range of variables with values
from a test's description. For example, a test for an invalid
distribution may contain the simpie line "Distribution: apple" and
nothing else. Sometimes there will be copied template that was
modified in some way, such as a 'changelog.in', which denotes a
template to be filled, that has offensive entries, invalid version
numbers, long line length or extra whitespace. It's usually super
obvious.

Sometimes test writers even seem to have a sense of humor. For
example, URLs are exempt from line length restrictions. One test uses
a fictional example:

http://www.example.com/but-a-really-long-url-does-not-count-as-a-long-line-at-all

Test are our first line of defense against the angry hoardes. The test
suite now has almost a thousand test cases that exercise almost all of
the approximately 1,400 tags. About a dozen are currently
untested. There may be none by the time you read this. Between the
checks, which are usually simpler than you might assume, and the test
case it's usually obvious what's going on. If the tests pass, Lintian
is almost certainly right. And we need it to be right. It reduces
anger among our consumers and reduces the email load on
maintainers. Testing is what Lintian is all about.

This manual will show you how to write your own tests to support your
own checks. A working test of your contribution to Lintian will make
you feel good. I have been working a lot with Lintian's test
suite. There is no more relaxing feeling when everything runs
smoothly.

The problems occur when things are not running smoothly. It usually
causes great anguish for someone on the team. The time frame of this
anguish between discovery and resolution is directly related to your
tests specificity. A test that triggers many tags is complicated and
takes more time to investigate. Many tests that trigger many tags can
be impossible to understand and correct. One of the important parts of
this manual is to learn discipline about writing good tests.

The setup is actually logical. You edit a check (which is what Lintian
calls the routine that tests your package) and then have to make sure
it does what you think. The check is therefore the basic testable
entity. The test suite's basic job is to provide good feedback when
your editing job went awry. Maybe you accidentally changed the logic
of a related tag, or you simply didn't implement what you
intended. There is a myriad of possibilities. The key to a quick
resolution are specific tests. Usually the test name will already give
it away when something went wrong. Next, you will look at the tag
differential between expected and actual tags, which looks like a
standard diff. There is your false positive! Then you make more edits,
and finally submit your merge request on Salsa.

Welcome to Lintian! We would love to have more
contributors.

Personally, I think Lintian could easily have ten times as many tags
as it has now. We will probably have to delegate some areas to teams
of dedicated specialists, for example related to Java, or
cross-building. There may be a private name space for your work, let's
say for anything related to nodejs. That's right, you can pick any tag
name you like!

For such a distributed model to work, everybody has to learn how to
write tests. Lintian may also enforce that all tags are tested. That
is where this manual comes in. It's going to be people's effort.

Let's start with an example:
