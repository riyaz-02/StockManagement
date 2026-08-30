import {
  EC2Client,
  DescribeInstancesCommand,
  StartInstancesCommand,
  waitUntilInstanceRunning,
} from '@aws-sdk/client-ec2';

const jsonResponse = (statusCode, body) => ({
  statusCode,
  headers: {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'content-type',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Content-Type': 'application/json',
  },
  body: JSON.stringify(body),
});

const requiredEnv = (name) => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
};

const describeInstance = async (ec2, instanceId) => {
  const result = await ec2.send(new DescribeInstancesCommand({ InstanceIds: [instanceId] }));
  const instance = result.Reservations?.[0]?.Instances?.[0];
  if (!instance) throw new Error(`EC2 instance not found: ${instanceId}`);
  return instance;
};

const updateHostingerARecord = async ({ domain, recordName, publicIp, ttl, token }) => {
  const response = await fetch(`https://developers.hostinger.com/api/dns/v1/zones/${domain}`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      overwrite: true,
      zone: [
        {
          type: 'A',
          name: recordName,
          ttl,
          records: [{ content: publicIp }],
        },
      ],
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Hostinger DNS update failed (${response.status}): ${text}`);
  }
};

export const handler = async (event) => {
  if (event?.requestContext?.http?.method === 'OPTIONS') {
    return jsonResponse(204, {});
  }

  const instanceId = requiredEnv('EC2_INSTANCE_ID');
  const domain = process.env.HOSTINGER_DOMAIN || 'laltuguineapalace.com';
  const recordName = process.env.HOSTINGER_RECORD_NAME || 'api';
  const ttl = Number.parseInt(process.env.HOSTINGER_TTL_SECONDS || '60', 10);
  const token = requiredEnv('HOSTINGER_API_TOKEN');
  const apiUrl = `https://${recordName}.${domain}/api`;

  const ec2 = new EC2Client({});
  let instance = await describeInstance(ec2, instanceId);
  const state = instance.State?.Name;

  if (state === 'stopped') {
    await ec2.send(new StartInstancesCommand({ InstanceIds: [instanceId] }));
  }

  if (state !== 'running') {
    const waiter = await waitUntilInstanceRunning(
      { client: ec2, maxWaitTime: 180, minDelay: 5, maxDelay: 10 },
      { InstanceIds: [instanceId] }
    );

    if (waiter.state !== 'SUCCESS') {
      throw new Error(`EC2 did not reach running state: ${waiter.reason}`);
    }
  }

  instance = await describeInstance(ec2, instanceId);
  const publicIp = instance.PublicIpAddress;
  if (!publicIp) {
    throw new Error('EC2 is running but has no public IPv4 address. Enable auto-assign public IPv4 on the subnet/interface.');
  }

  await updateHostingerARecord({
    domain,
    recordName,
    publicIp,
    ttl: Number.isFinite(ttl) && ttl > 0 ? ttl : 60,
    token,
  });

  return jsonResponse(200, {
    ok: true,
    publicIp,
    apiUrl,
    message: `${recordName}.${domain} now points to ${publicIp}`,
  });
};
