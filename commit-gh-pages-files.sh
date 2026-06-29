#!/bin/bash

# Clean all staged, unstaged, tracked files first
cd public && git reset --hard HEAD && git clean -fdx && cd ..

hugo && cd public && git add --all && git commit -m "Publishing to master" && cd ..
