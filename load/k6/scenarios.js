import http from "k6/http";
import {
  check,
  sleep,
} from "k6";

const scenarioName = __ENV.K6_SCENARIO || "healthy";

const targetUrl = (
  __ENV.K6_TARGET_URL
  || "http://api-load-target:3000"
);

const scenarioDefinitions = {
  healthy: {
    executor: "constant-vus",
    vus: 2,
    duration: "10s",
    exec: "healthy",
  },

  latency: {
    executor: "constant-vus",
    vus: 2,
    duration: "10s",
    exec: "latency",
  },

  http500: {
    executor: "constant-vus",
    vus: 2,
    duration: "10s",
    exec: "http500",
  },
};

if (!(scenarioName in scenarioDefinitions)) {
  throw new Error(
    `Unsupported K6_SCENARIO: ${scenarioName}`
  );
}

export const options = {
  scenarios: {
    [scenarioName]:
      scenarioDefinitions[scenarioName],
  },

  thresholds: {
    checks: [
      "rate>0.99",
    ],
  },
};

export function setup() {
  const attempts = 30;

  for (
    let attempt = 1;
    attempt <= attempts;
    attempt += 1
  ) {
    const response = http.get(
      `${targetUrl}/healthz`,
      {
        tags: {
          lab_scenario: "readiness",
        },
      }
    );

    if (response.status === 200) {
      return {
        targetUrl,
      };
    }

    if (attempt < attempts) {
      sleep(1);
    }
  }

  throw new Error(
    "Load-test API did not become ready"
  );
}

export function healthy(data) {
  const response = http.get(
    `${data.targetUrl}/api/work`,
    {
      tags: {
        lab_scenario: "healthy",
      },
    }
  );

  check(
    response,
    {
      "healthy status is 200":
        (res) => res.status === 200,
    }
  );

  sleep(0.1);
}

export function latency(data) {
  const response = http.get(
    `${data.targetUrl}/api/slow?ms=500`,
    {
      tags: {
        lab_scenario: "latency",
      },
    }
  );

  check(
    response,
    {
      "latency status is 200":
        (res) => res.status === 200,

      "controlled latency is at least 450 ms":
        (res) => res.timings.duration >= 450,

      "controlled latency stays below 2000 ms":
        (res) => res.timings.duration < 2000,
    }
  );
}

export function http500(data) {
  const response = http.get(
    `${data.targetUrl}/api/error`,
    {
      tags: {
        lab_scenario: "http500",
      },
    }
  );

  check(
    response,
    {
      "controlled error status is 500":
        (res) => res.status === 500,
    }
  );

  sleep(0.1);
}
