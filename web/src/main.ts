import { mount } from 'svelte';
import './styles/accent.css';
import './styles/fonts.css';
import './styles/type.css';
import './styles/unfold.css';
import './styles/app.css';
import './styles/placement-hud.css';
import './styles/prompt.css';
import App from './App.svelte';

mount(App, { target: document.body });
