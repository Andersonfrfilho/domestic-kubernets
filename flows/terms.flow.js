#!/usr/bin/env node

const path = require('path');
const { loadEnv, resolveEnvFile } = require('./lib/env');
const { request } = require('./lib/http');
const { Report } = require('./lib/report');

const envFile = resolveEnvFile(process.argv[3]);
const env = loadEnv(envFile);

const BASE = env.KONG_URL || 'http://192.168.1.200';
const userId = process.argv[2];

if (!userId) {
  console.error('Uso: node terms.flow.js <user-keycloak-id> [env-file]');
  process.exit(1);
}

const report = new Report('Terms Versioning Flow');

async function run() {
  console.log(`${'═'.repeat(60)}`);
  console.log(`  Terms Versioning Flow — Executando via Kong`);
  console.log(`  User ID: ${userId}`);
  console.log(`${'═'.repeat(60)}\n`);

  report.setContext('userId', userId);

  // ── Step 1: Get current terms version ──────────────────────────────
  console.log(`  → Step 1: Obter versão ativa atual`);
  try {
    const res = await request(BASE, '/bff/auth/terms/current', 'GET');
    report.addStep('Obter versão ativa atual', res.ok ? 'pass' : 'fail', {
      method: 'GET',
      path: '/bff/auth/terms/current',
      status: res.status,
      body: typeof res.data === 'object' ? res.data : null,
    });
    if (res.ok && res.data) {
      report.setContext('currentVersion', res.data.version);
      report.setContext('currentVersionId', res.data.id);
      console.log(`    Versão: ${res.data.version} — ${res.data.title}`);
    }
  } catch (err) {
    report.addStep('Obter versão ativa atual', 'fail', {
      method: 'GET',
      path: '/bff/auth/terms/current',
      error: err.message,
    });
    console.log(`    Erro: ${err.message}`);
  }
  console.log();

  // ── Step 2: List all versions ─────────────────────────────────────
  console.log(`  → Step 2: Listar todas as versões`);
  try {
    const res = await request(BASE, '/bff/auth/terms/versions', 'GET');
    report.addStep('Listar todas as versões', res.ok ? 'pass' : 'fail', {
      method: 'GET',
      path: '/bff/auth/terms/versions',
      status: res.status,
      body: typeof res.data === 'object' ? res.data : null,
    });
    if (res.ok && Array.isArray(res.data)) {
      console.log(`    Total de versões: ${res.data.length}`);
      res.data.forEach((v) => {
        const active = v.isActive ? ' (ativa)' : '';
        console.log(`    - ${v.version}: ${v.title}${active}`);
      });
    }
  } catch (err) {
    report.addStep('Listar todas as versões', 'fail', {
      method: 'GET',
      path: '/bff/auth/terms/versions',
      error: err.message,
    });
    console.log(`    Erro: ${err.message}`);
  }
  console.log();

  // ── Step 3: Check pending terms (before accept) ───────────────────
  console.log(`  → Step 3: Verificar termos pendentes (antes de aceitar)`);
  try {
    const res = await request(BASE, '/bff/auth/terms/check-pending', 'POST', { userId });
    report.addStep('Verificar pendência (antes)', res.ok ? 'pass' : 'fail', {
      method: 'POST',
      path: '/bff/auth/terms/check-pending',
      status: res.status,
      body: typeof res.data === 'object' ? res.data : null,
    });
    if (res.ok && res.data) {
      report.setContext('pendingBefore', res.data.hasPending ? 'Sim' : 'Não');
      console.log(`    Pendente: ${res.data.hasPending ? 'Sim' : 'Não'}`);
      console.log(`    Última aceita: ${res.data.lastAcceptedVersion || 'Nunca'}`);
    }
  } catch (err) {
    report.addStep('Verificar pendência (antes)', 'fail', {
      method: 'POST',
      path: '/bff/auth/terms/check-pending',
      error: err.message,
    });
    console.log(`    Erro: ${err.message}`);
  }
  console.log();

  // ── Step 4: Accept terms ──────────────────────────────────────────
  console.log(`  → Step 4: Aceitar termos`);
  const currentVersionId = report.getContext('currentVersionId');
  if (!currentVersionId) {
    report.addStep('Aceitar termos', 'skip', {
      method: 'POST',
      path: '/bff/auth/terms/accept',
      error: 'Sem versão ativa disponível',
    });
    console.log(`    Pulado: sem versão ativa`);
  } else {
    try {
      const res = await request(BASE, '/bff/auth/terms/accept', 'POST', {
        userId,
        termsVersionId: currentVersionId,
      });
      report.addStep('Aceitar termos', res.ok ? 'pass' : 'fail', {
        method: 'POST',
        path: '/bff/auth/terms/accept',
        status: res.status,
        body: typeof res.data === 'object' ? res.data : null,
      });
      if (res.ok) console.log(`    Aceitos — versão: ${res.data?.termsVersion}`);
    } catch (err) {
      report.addStep('Aceitar termos', 'fail', {
        method: 'POST',
        path: '/bff/auth/terms/accept',
        error: err.message,
      });
      console.log(`    Erro: ${err.message}`);
    }
  }
  console.log();

  // ── Step 5: Check pending terms (after accept) ────────────────────
  console.log(`  → Step 5: Verificar termos pendentes (após aceitar)`);
  try {
    const res = await request(BASE, '/bff/auth/terms/check-pending', 'POST', { userId });
    report.addStep('Verificar pendência (depois)', res.ok ? 'pass' : 'fail', {
      method: 'POST',
      path: '/bff/auth/terms/check-pending',
      status: res.status,
      body: typeof res.data === 'object' ? res.data : null,
    });
    if (res.ok && res.data) {
      report.setContext('pendingAfter', res.data.hasPending ? 'Sim' : 'Não');
      console.log(`    Pendente: ${res.data.hasPending ? 'Sim' : 'Não'}`);
    }
  } catch (err) {
    report.addStep('Verificar pendência (depois)', 'fail', {
      method: 'POST',
      path: '/bff/auth/terms/check-pending',
      error: err.message,
    });
    console.log(`    Erro: ${err.message}`);
  }
  console.log();

  // ── Print final report ────────────────────────────────────────────
  report.print();

  const result = report.steps.filter((s) => s.status === 'fail');
  process.exit(result.length > 0 ? 1 : 0);
}

run().catch((err) => {
  console.error(`Fatal error: ${err.message}`);
  process.exit(1);
});
