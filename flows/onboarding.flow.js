#!/usr/bin/env node

const path = require('path');
const { loadEnv, resolveEnvFile } = require('./lib/env');
const { request } = require('./lib/http');
const { Report } = require('./lib/report');

const envFile = resolveEnvFile(process.argv[2]);
const env = loadEnv(envFile);

const BASE = env.KONG_URL || 'http://192.168.1.200';
const report = new Report('Onboarding Flow');

async function run() {
  console.log(`${'═'.repeat(60)}`);
  console.log(`  Onboarding Flow — Executando via Kong`);
  console.log(`${'═'.repeat(60)}\n`);

  // ── Step 1: Get current terms version ──────────────────────────────
  console.log(`  → Step 1: Obter versão atual dos termos`);
  try {
    const res = await request(BASE, '/bff/auth/terms/current', 'GET');
    report.addStep('Obter versão atual dos termos', res.ok ? 'pass' : 'fail', {
      method: 'GET',
      path: '/bff/auth/terms/current',
      status: res.status,
      body: typeof res.data === 'object' ? res.data : null,
    });
    if (res.ok && res.data?.id) {
      report.setContext('termsVersionId', res.data.id);
      report.setContext('termsVersion', res.data.version);
      console.log(`    Versão: ${res.data.version} — ID: ${res.data.id}`);
    }
  } catch (err) {
    report.addStep('Obter versão atual dos termos', 'fail', {
      method: 'GET',
      path: '/bff/auth/terms/current',
      error: err.message,
    });
    console.log(`    Erro: ${err.message}`);
  }
  console.log();

  // ── Step 2: Send verification code (QA Mode) ───────────────────────
  console.log(`  → Step 2: Enviar código de verificação (QA Mode)`);
  try {
    const res = await request(BASE, '/bff/onboarding/verification/send', 'POST', {
      destination: env.REGISTER_EMAIL,
      type: 'email',
    });
    report.addStep('Enviar código de verificação', res.ok ? 'pass' : 'fail', {
      method: 'POST',
      path: '/bff/onboarding/verification/send',
      status: res.status,
      body: typeof res.data === 'object' ? res.data : null,
    });
    if (res.ok) console.log(`    Código enviado (QA Mode: email=0000)`);
  } catch (err) {
    report.addStep('Enviar código de verificação', 'fail', {
      method: 'POST',
      path: '/bff/onboarding/verification/send',
      error: err.message,
    });
    console.log(`    Erro: ${err.message}`);
  }
  console.log();

  // ── Step 3: Verify code (QA Mode — code=0000) ─────────────────────
  console.log(`  → Step 3: Verificar código (QA Mode — 0000)`);
  try {
    const res = await request(BASE, '/bff/onboarding/verification/verify', 'POST', {
      destination: env.REGISTER_EMAIL,
      type: 'email',
      code: '0000',
    });
    report.addStep('Verificar código', res.ok ? 'pass' : 'fail', {
      method: 'POST',
      path: '/bff/onboarding/verification/verify',
      status: res.status,
      body: typeof res.data === 'object' ? res.data : null,
    });
    if (res.ok) console.log(`    Código verificado com sucesso`);
  } catch (err) {
    report.addStep('Verificar código', 'fail', {
      method: 'POST',
      path: '/bff/onboarding/verification/verify',
      error: err.message,
    });
    console.log(`    Erro: ${err.message}`);
  }
  console.log();

  // ── Step 4: Register user ─────────────────────────────────────────
  console.log(`  → Step 4: Cadastrar usuário`);
  try {
    const res = await request(BASE, '/bff/onboarding/register', 'POST', {
      email: env.REGISTER_EMAIL,
      password: env.REGISTER_PASSWORD,
      firstName: env.REGISTER_FIRST_NAME,
      lastName: env.REGISTER_LAST_NAME,
      phone: env.REGISTER_PHONE,
      cpf: env.REGISTER_CPF,
    });
    report.addStep('Cadastrar usuário', res.ok ? 'pass' : 'fail', {
      method: 'POST',
      path: '/bff/onboarding/register',
      status: res.status,
      body: typeof res.data === 'object' ? res.data : null,
    });
    if (res.ok && res.data?.keycloakId) {
      report.setContext('keycloakId', res.data.keycloakId);
      console.log(`    Usuário criado — Keycloak ID: ${res.data.keycloakId}`);
    }
  } catch (err) {
    report.addStep('Cadastrar usuário', 'fail', {
      method: 'POST',
      path: '/bff/onboarding/register',
      error: err.message,
    });
    console.log(`    Erro: ${err.message}`);
  }
  console.log();

  // ── Step 5: Lookup CEP ────────────────────────────────────────────
  console.log(`  → Step 5: Consultar CEP (01001000)`);
  try {
    const res = await request(BASE, '/bff/onboarding/cep/01001000', 'GET');
    report.addStep('Consultar CEP', res.ok ? 'pass' : 'fail', {
      method: 'GET',
      path: '/bff/onboarding/cep/01001000',
      status: res.status,
      body: typeof res.data === 'object' ? res.data : null,
    });
    if (res.ok && res.data?.street) {
      console.log(`    ${res.data.street}, ${res.data.neighborhood} — ${res.data.city}/${res.data.state}`);
    }
  } catch (err) {
    report.addStep('Consultar CEP', 'fail', {
      method: 'GET',
      path: '/bff/onboarding/cep/01001000',
      error: err.message,
    });
    console.log(`    Erro: ${err.message}`);
  }
  console.log();

  // ── Step 6: Accept terms ──────────────────────────────────────────
  console.log(`  → Step 6: Aceitar termos de uso`);
  const keycloakId = report.getContext('keycloakId');
  const termsVersionId = report.getContext('termsVersionId');

  if (!keycloakId) {
    report.addStep('Aceitar termos de uso', 'skip', {
      method: 'POST',
      path: '/bff/auth/terms/accept',
      error: 'Sem Keycloak ID — cadastro falhou',
    });
    console.log(`    Pulado: sem Keycloak ID`);
  } else {
    try {
      const res = await request(BASE, '/bff/auth/terms/accept', 'POST', {
        userId: keycloakId,
        termsVersionId: termsVersionId || undefined,
      });
      report.addStep('Aceitar termos de uso', res.ok ? 'pass' : 'fail', {
        method: 'POST',
        path: '/bff/auth/terms/accept',
        status: res.status,
        body: typeof res.data === 'object' ? res.data : null,
      });
      if (res.ok) console.log(`    Termos aceitos — versão: ${res.data?.termsVersion || termsVersionId}`);
    } catch (err) {
      report.addStep('Aceitar termos de uso', 'fail', {
        method: 'POST',
        path: '/bff/auth/terms/accept',
        error: err.message,
      });
      console.log(`    Erro: ${err.message}`);
    }
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
