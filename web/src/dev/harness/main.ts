import { mount } from 'svelte';
import '../../styles/accent.css';
import './harness.css';
import Harness from './Harness.svelte';

mount(Harness, { target: document.body });
