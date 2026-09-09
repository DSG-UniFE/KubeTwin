# Workflow Modeling

This document describes how workflows can be modeled in KubeTwin.

## Overview

KubeTwin supports three workflow patterns:

1. Simple sequential workflows
2. Parallel branches
3. Nested orchestrated calls

The original sequential format is still supported, so existing configurations do not need to be rewritten.

## 1. Simple Sequential Workflow

Use `component_sequence` with plain steps.

```ruby
workflow_types \
  1 => {
    component_sequence: [
      { name: "productpage" },
      { name: "details" },
      { name: "reviews" },
      { name: "ratings" }
    ]
  }
```

This models a simple chain where each component directly forwards the request to the next one.

## 2. Parallel Branches

Use a step with `type: "parallel"` and a list of `branches`.

```ruby
workflow_types \
  1 => {
    component_sequence: [
      { name: "frontend" },
      {
        type: "parallel",
        branches: [
          { name: "service_a" },
          { name: "service_b" }
        ],
        wait_for: "all"
      },
      { name: "aggregator" }
    ]
  }
```

Each branch is dispatched independently. The parent request resumes only when all branches complete.

### Multi-step parallel branches

Branches can contain their own local sequence.

```ruby
workflow_types \
  1 => {
    component_sequence: [
      { name: "frontend" },
      {
        type: "parallel",
        branches: [
          { name: "service_a" },
          {
            name: "service_b",
            component_sequence: [
              { name: "service_b" },
              { name: "service_c" }
            ]
          }
        ],
        wait_for: "all"
      }
    ]
  }
```

## 3. Nested Orchestrated Calls

Use `calls` on a named component when that component orchestrates downstream calls and remains logically blocked until they complete.

```ruby
workflow_types \
  1 => {
    component_sequence: [
      {
        name: "productpage",
        calls: [
          { name: "details" },
          {
            name: "reviews",
            calls: [
              { name: "ratings" }
            ]
          }
        ]
      }
    ]
  }
```

This models:

1. `productpage` executes locally
2. `productpage` calls `details`
3. control returns to `productpage`
4. `productpage` calls `reviews`
5. `reviews` calls `ratings`
6. control returns to `reviews`
7. control returns to `productpage`

This is useful for request/response workflows where the parent service orchestrates the call graph instead of forwarding the request as a pure chain.

## Choosing the Right Pattern

Use a simple sequential workflow when each service directly forwards the request to the next one.

Use `parallel` when multiple branches are active at the same time and the parent waits for all of them.

Use `calls` when a service acts as an orchestrator and issues downstream calls one after another, regaining control after each response.

## Backward Compatibility

Existing sequential workflows continue to work unchanged.

The new `calls` field is optional and only affects steps that explicitly use it.
