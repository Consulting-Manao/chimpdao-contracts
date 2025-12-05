/**
 * Test blocksec2go commands to see actual output
 */

import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

async function test() {
  console.log('Testing blocksec2go commands...\n');
  
  // Test 1: Get card info
  console.log('1. Testing get_card_info:');
  try {
    const { stdout, stderr } = await execAsync('uv run --with blocksec2go blocksec2go get_card_info');
    console.log('STDOUT:', stdout);
    if (stderr) console.log('STDERR:', stderr);
  } catch (error) {
    console.error('Error:', error.message);
    if (error.stdout) console.log('STDOUT:', error.stdout);
    if (error.stderr) console.log('STDERR:', error.stderr);
  }
  
  console.log('\n2. Testing help to see available commands:');
  try {
    const { stdout } = await execAsync('uv run --with blocksec2go blocksec2go --help');
    console.log(stdout);
  } catch (error) {
    console.error('Error:', error.message);
  }
}

test();

