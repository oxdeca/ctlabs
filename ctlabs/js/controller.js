/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/controller.js
 Description : WebUI helpers for the GLOBAL control-plane cards (Control-Plane
               nodes + Exposed Services). The Ansible/Terraform cards reuse the
               shared automation.js editor via the controller wrappers defined
               there. All endpoints live under /controller/*.
 License     : MIT License
 -----------------------------------------------------------------------------
*/

  window.controllerAddService = async function(event) {
      event.preventDefault();
      const form = event.currentTarget || event.target;
      const fd   = new FormData(form);
      try {
          const res = await fetch('/controller/services', { method: 'POST', body: fd });
          const data = await res.json().catch(() => ({}));
          if (!res.ok) throw new Error(data.error || 'Failed to add service');
          window.location.reload();
      } catch (err) {
          alert('Error: ' + err.message);
      }
      return false;
  };

  window.deleteControllerService = async function(node, ext, int, proto) {
      if (!confirm(`Remove exposed service ${node} : ${ext} -> ${int}/${proto}?`)) return;
      const fd = new FormData();
      fd.append('node', node);
      fd.append('ext', ext);
      fd.append('int', int);
      fd.append('proto', proto);
      try {
          const res = await fetch('/controller/services/delete', { method: 'POST', body: fd });
          const data = await res.json().catch(() => ({}));
          if (!res.ok || data.success === false) throw new Error(data.error || 'Failed to remove service');
          window.location.reload();
      } catch (err) {
          alert('Error: ' + err.message);
      }
  };

  window.controllerAddNode = async function(event) {
      event.preventDefault();
      const form = event.currentTarget || event.target;
      const fd   = new FormData(form);
      try {
          const res = await fetch('/controller/nodes', { method: 'POST', body: fd });
          const data = await res.json().catch(() => ({}));
          if (!res.ok || data.success === false) throw new Error(data.error || 'Failed to add node');
          if (data.message) alert(data.message);
          window.location.reload();
      } catch (err) {
          alert('Error: ' + err.message);
      }
      return false;
  };

  window.deleteControllerNode = async function(name) {
      if (!confirm(`Remove control-plane node '${name}' (and its exposed services)?`)) return;
      const fd = new FormData();
      fd.append('name', name);
      try {
          const res = await fetch('/controller/nodes/delete', { method: 'POST', body: fd });
          const data = await res.json().catch(() => ({}));
          if (!res.ok || data.success === false) throw new Error(data.error || 'Failed to remove node');
          if (data.message) alert(data.message);
          window.location.reload();
      } catch (err) {
          alert('Error: ' + err.message);
      }
  };
