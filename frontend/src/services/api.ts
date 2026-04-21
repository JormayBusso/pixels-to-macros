import axios from 'axios';

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL ?? '/api',
  timeout: 60_000,
});

// Attach stored token to every request
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('nutrilens_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// On 401 clear auth and redirect to login
api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('nutrilens_token');
      window.location.href = '/login';
    }
    return Promise.reject(err);
  },
);

export default api;
