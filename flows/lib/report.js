const C = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  dim: '\x1b[2m',
  bold: '\x1b[1m',
};

class Report {
  constructor(flowName) {
    this.flowName = flowName;
    this.steps = [];
    this.startTime = Date.now();
    this.context = {};
  }

  addStep(name, status, details = {}) {
    this.steps.push({ name, status, details, timestamp: new Date().toISOString() });
  }

  setContext(key, value) {
    this.context[key] = value;
  }

  getContext(key) {
    return this.context[key];
  }

  print() {
    const duration = ((Date.now() - this.startTime) / 1000).toFixed(2);
    const passed = this.steps.filter((s) => s.status === 'pass').length;
    const failed = this.steps.filter((s) => s.status === 'fail').length;
    const skipped = this.steps.filter((s) => s.status === 'skip').length;
    const total = this.steps.length;

    const line = `${C.cyan}${'═'.repeat(60)}${C.reset}`;
    const dash = `${C.cyan}${'─'.repeat(60)}${C.reset}`;

    console.log('\n');
    console.log(line);
    console.log(`${C.bold}${C.cyan}  ${this.flowName} — Relatório Final${C.reset}`);
    console.log(line);
    console.log();

    console.log(`${C.bold}  Etapas:${C.reset}`);
    console.log();

    this.steps.forEach((step, i) => {
      const num = String(i + 1).padStart(2, ' ');
      const icon = step.status === 'pass' ? '✓' : step.status === 'fail' ? '✗' : '–';
      const color = step.status === 'pass' ? C.green : step.status === 'fail' ? C.red : C.yellow;

      console.log(`  ${color}${icon} Step ${num}: ${step.name}${C.reset}`);

      if (step.details.method) {
        console.log(`     ${C.dim}${step.details.method} ${step.details.path}${C.reset}`);
      }

      if (step.details.status !== undefined) {
        const sc = step.details.status >= 200 && step.details.status < 300 ? C.green : C.red;
        console.log(`     ${C.dim}HTTP:${C.reset} ${sc}${step.details.status}${C.reset}`);
      }

      if (step.details.error) {
        console.log(`     ${C.red}Erro: ${step.details.error}${C.reset}`);
      }

      if (step.details.body && typeof step.details.body === 'object') {
        const json = JSON.stringify(step.details.body, null, 2);
        const lines = json.split('\n');
        const preview = lines.slice(0, 6).join('\n');
        console.log(`     ${C.dim}${preview}${C.reset}`);
        if (lines.length > 6) {
          console.log(`     ${C.dim}     ... +${lines.length - 6} linhas${C.reset}`);
        }
      }
      console.log();
    });

    console.log(dash);
    console.log();

    console.log(`${C.bold}  Resumo:${C.reset}`);
    console.log(`    ${C.green}✓ Aprovadas: ${passed}${C.reset}`);
    console.log(`    ${C.red}✗ Falharam:  ${failed}${C.reset}`);
    if (skipped > 0) console.log(`    ${C.yellow}– Puladas:   ${skipped}${C.reset}`);
    console.log(`    ${C.dim}Total:      ${total}${C.reset}`);
    console.log(`    ${C.dim}Duração:    ${duration}s${C.reset}`);
    console.log();

    if (Object.keys(this.context).length > 0) {
      console.log(`${C.bold}  Contexto:${C.reset}`);
      for (const [key, value] of Object.entries(this.context)) {
        console.log(`    ${C.dim}${key}:${C.reset} ${value}`);
      }
      console.log();
    }

    if (failed === 0) {
      console.log(`${C.green}${C.bold}  ✓ Fluxo concluído com sucesso${C.reset}`);
    } else {
      console.log(`${C.red}${C.bold}  ✗ Fluxo concluído com ${failed} falha(s)${C.reset}`);
    }

    console.log(line);
    console.log('\n');

    return { passed, failed, skipped, total, duration };
  }
}

module.exports = { Report };
