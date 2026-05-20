using UnityEngine;
using UnityEngine.InputSystem;
using System.Collections;
using UnityEngine.SceneManagement;
using TMPro;

public class VRShoot : MonoBehaviour
{
    public Camera cam;
    public float range = 100f;
    public int points = 0;
    public TMP_Text scoreText;

    public Renderer dotRenderer;
    public AudioClip hitSound;
    public AudioClip shootSound;

    public Color normalColor = Color.white;
    public Color hitColor = Color.red;

    void Update()
    {
        if (Touchscreen.current != null &&
            Touchscreen.current.primaryTouch.press.wasPressedThisFrame)
        {
            Shoot();
        }
    }

    void Shoot()
    {
        Ray ray = new Ray(cam.transform.position, cam.transform.forward);
        AudioSource.PlayClipAtPoint(shootSound, cam.transform.position);
        if (Physics.Raycast(ray, out RaycastHit hit, range))
        {
            Debug.Log("Golpeado: " + hit.collider.name);

            if (hit.collider.CompareTag("Enemy"))
            {
                AudioSource.PlayClipAtPoint(hitSound, hit.point);
                Destroy(hit.collider.gameObject);
                points++;
                scoreText.text = points.ToString();
                StartCoroutine(HitEffect());
            }
            // START BUTTON
            if (hit.collider.CompareTag("StartButton"))
            {
                Debug.Log("Start Button pressed");
                points = 0;
                scoreText.text = points.ToString();
                UnityEngine.SceneManagement.SceneManager.LoadScene("Main");
            }

            // EXIT BUTTON
            if (hit.collider.CompareTag("ExitButton"))
            {
                Application.Quit();
            }
        }
    }

    IEnumerator HitEffect()
    {
        dotRenderer.material.color = hitColor;

        yield return new WaitForSeconds(0.5f);

        dotRenderer.material.color = normalColor;
    }
}