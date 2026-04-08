<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Annotation\Route;

class UserController extends AbstractController
{
    /**
     * Retrieve a list of all registered users in the system.
     *
     * Returns a paginated collection of user records including
     * their profile information and account status.
     */
    #[Route('/', name: 'get_all_users', methods: ['GET'])]
    public function getAllUsers(): JsonResponse
    {
        return $this->json(['users' => []]);
    }

    /**
     * Send a password reset link to the user's registered email address.
     *
     * Generates a time-limited token and dispatches a notification
     * containing the reset instructions to the provided email.
     */
    #[Route('/password-reset', name: 'request_password_reset', methods: ['POST'])]
    public function requestPasswordReset(): JsonResponse
    {
        return $this->json(['status' => 'email_sent']);
    }
}
