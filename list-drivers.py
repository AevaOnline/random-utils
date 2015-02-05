#!/usr/bin/env python

# enumerate entrypoints in the "ironic.drivers" namespace

import pkg_resources as pkg
print [p.name for p in pkg.iter_entry_points("ironic.drivers") if not p.name.startswith("fake")]

